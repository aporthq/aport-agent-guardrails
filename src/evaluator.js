#!/usr/bin/env node
/**
 * @deprecated Use @aporthq/aport-agent-guardrails-core (Evaluator, verify/verifySync) instead.
 * This legacy CommonJS API client is kept for backward compatibility only.
 *
 * APort Generic Policy Evaluator - API Client
 *
 * This is a lightweight wrapper that calls the APort cloud API for policy evaluation.
 * For local-first evaluation, the cloud API validates passports and policies without
 * storing sensitive data.
 *
 * Usage:
 *   const { evaluatePolicy } = require('./evaluator');
 *   const decision = await evaluatePolicy(policyPack, passport, context);
 */

const fs = require("fs");
const path = require("path");

/**
 * Evaluate a policy using the APort API.
 *
 * The API supports (see agent-passport functions/api/verify/policy/[pack_id].ts):
 * - Passport: (1) context.agent_id (cloud); (2) body.passport (local via API).
 * - Policy: (1) pack_id in URL path (registry); (2) pack_id=IN_BODY + body.policy (policy in request body).
 * Local evaluation (no API) is coming soon.
 *
 * @param {object} policyPack - Policy pack JSON (from external/aport-policies or dynamic). Must have id or policy_id.
 * @param {object|null} passport - Agent passport JSON (required for local mode; null for cloud mode)
 * @param {object} context - Action context (tool parameters, etc.)
 * @param {object} options - Optional settings
 * @param {string} options.apiUrl - API endpoint base URL. Env: APORT_API_URL.
 * @param {string} options.apiKey - API key (optional). Env: APORT_API_KEY.
 * @param {string} options.agentId - For cloud mode: agent_id in registry. Env: APORT_AGENT_ID.
 * @param {boolean} options.policyInBody - If true, POST to /api/verify/policy/IN_BODY and send body.policy (for dynamic/generated policies).
 * @returns {Promise<object>} OAP v1.0 compliant decision object
 */
async function evaluatePolicy(policyPack, passport, context, options = {}) {
  const apiUrl = (
    options.apiUrl ||
    process.env.APORT_API_URL ||
    "https://api.aport.io"
  ).replace(/\/$/, "");
  const apiKey = options.apiKey || process.env.APORT_API_KEY;
  const agentId = options.agentId || process.env.APORT_AGENT_ID;
  const policyInBody = options.policyInBody === true;

  const packId = (policyPack && (policyPack.id || policyPack.policy_id)) || "";
  if (!policyPack || !packId) {
    throw new Error("Invalid policy pack: missing id or policy_id field");
  }
  if (!context || typeof context !== "object") {
    throw new Error("Invalid context: must be an object");
  }

  // Policy: pack_id in path (default) or IN_BODY with body.policy (agent-passport API)
  const pathPackId = policyInBody ? "IN_BODY" : packId;
  const url = `${apiUrl}/api/verify/policy/${pathPackId}`;
  const headers = { "Content-Type": "application/json" };
  if (apiKey) {
    headers["Authorization"] = `Bearer ${apiKey}`;
  }

  let bodyObj;
  if (agentId) {
    bodyObj = {
      context: { agent_id: agentId, ...context },
    };
  } else if (passport && (passport.passport_id || passport.agent_id)) {
    const passportForApi = {
      ...passport,
      agent_id: passport.agent_id || passport.passport_id,
    };
    bodyObj = {
      passport: passportForApi,
      context,
    };
  } else {
    throw new Error(
      "Either pass a passport (local mode) or set APORT_AGENT_ID / options.agentId (cloud mode)"
    );
  }
  if (policyInBody) {
    bodyObj.policy = policyPack;
  }
  const body = JSON.stringify(bodyObj);

  try {
    const response = await fetch(url, {
      method: "POST",
      headers,
      body,
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`API request failed (${response.status}): ${errorText}`);
    }

    const data = await response.json();
    // API may return { decision: {...} } (e.g. self-hosted) or the decision object directly
    const decision =
      data.decision && typeof data.decision === "object" ? data.decision : data;

    if (!decision.decision_id || typeof decision.allow !== "boolean") {
      throw new Error("Invalid decision response: missing required fields");
    }

    return decision;
  } catch (error) {
    return {
      decision_id: `local-error-${Date.now()}`,
      policy_id: packId,
      passport_id: (passport && passport.passport_id) || "unknown",
      owner_id: (passport && passport.owner_id) || "unknown",
      assurance_level: (passport && passport.assurance_level) || "L0",
      allow: false,
      reasons: [
        {
          code: "oap.evaluation_error",
          message: error.message || "Policy evaluation failed",
        },
      ],
      issued_at: new Date().toISOString(),
      expires_at: new Date(Date.now() + 3600000).toISOString(),
      passport_digest: "sha256:error",
      signature: "ed25519:unsigned",
      kid: "oap:local:error",
    };
  }
}

/**
 * Load policy pack from external/aport-policies submodule
 *
 * @param {string} policyId - Policy pack ID (e.g., 'system.command.execute.v1')
 * @returns {object} Policy pack JSON
 */
function loadPolicyPack(policyId) {
  const scriptDir = path.join(__dirname, "..");
  const policiesDir = path.join(scriptDir, "external", "aport-policies");

  // Try versioned directory first
  const policyDir = path.join(policiesDir, policyId);
  const policyFile = path.join(policyDir, "policy.json");

  if (fs.existsSync(policyFile)) {
    return JSON.parse(fs.readFileSync(policyFile, "utf8"));
  }

  // Try local overrides
  const localOverrides = path.join(
    scriptDir,
    "local-overrides",
    "policies",
    `${policyId}.json`
  );
  if (fs.existsSync(localOverrides)) {
    return JSON.parse(fs.readFileSync(localOverrides, "utf8"));
  }

  throw new Error(`Policy pack not found: ${policyId}`);
}

/**
 * Load passport from standard location
 *
 * @param {string} passportPath - Path to passport file (default: ~/.openclaw/passport.json)
 * @returns {object} Passport JSON
 */
function loadPassport(passportPath) {
  const defaultPath = path.join(process.env.HOME, ".openclaw", "passport.json");
  const filePath =
    passportPath || process.env.OPENCLAW_PASSPORT_FILE || defaultPath;

  if (!fs.existsSync(filePath)) {
    throw new Error(`Passport file not found: ${filePath}`);
  }

  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

/**
 * Write decision to standard location
 *
 * @param {object} decision - Decision object
 * @param {string} decisionPath - Path to write decision (default: ~/.openclaw/decision.json)
 */
function writeDecision(decision, decisionPath) {
  const defaultPath = path.join(process.env.HOME, ".openclaw", "decision.json");
  const filePath =
    decisionPath || process.env.OPENCLAW_DECISION_FILE || defaultPath;

  // Ensure directory exists
  const dir = path.dirname(filePath);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }

  fs.writeFileSync(filePath, JSON.stringify(decision, null, 2), "utf8");
}

module.exports = {
  evaluatePolicy,
  loadPolicyPack,
  loadPassport,
  writeDecision,
};

// CLI usage
if (require.main === module) {
  const [, , policyId, contextJson] = process.argv;

  if (!policyId) {
    console.error("Usage: node evaluator.js <policy_id> <context_json>");
    console.error(
      'Example: node evaluator.js system.command.execute.v1 \'{"command":"ls"}\''
    );
    process.exit(1);
  }

  (async () => {
    try {
      const policyPack = loadPolicyPack(policyId);
      const context = contextJson ? JSON.parse(contextJson) : {};

      let passport = null;
      if (!process.env.APORT_AGENT_ID) {
        passport = loadPassport();
      }

      console.log(
        `Evaluating policy: ${policyId} (${
          passport ? "local passport" : "cloud agent_id"
        })`
      );
      const decision = await evaluatePolicy(policyPack, passport, context);

      writeDecision(decision);

      console.log(`Decision: ${decision.allow ? "ALLOW" : "DENY"}`);
      console.log(
        `Reasons: ${decision.reasons.map((r) => r.message).join(", ")}`
      );

      process.exit(decision.allow ? 0 : 1);
    } catch (error) {
      console.error("Error:", error.message);
      process.exit(1);
    }
  })();
}
