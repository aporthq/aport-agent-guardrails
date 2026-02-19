/**
 * Node API guardrail performance harness — REAL API, all identity/policy variants.
 * Usage: node node_api_harness_real.cjs <iterations> <apiUrl> <variant> [identity]
 *   variant: agent_path | agent_body | passport_path | passport_body
 *   identity: for agent_* = agent_id; for passport_* = path to passport.json
 * Output: one line JSON array of latencies (ms).
 */
"use strict";

const fs = require("fs");
const path = require("path");

const iterations = Math.min(parseInt(process.argv[2], 10) || 50, 200);
const apiUrl = process.argv[3] || "https://api.aport.io";
const variant = process.argv[4] || "agent_path";
const identity = process.argv[5] || process.env.APORT_AGENT_ID;

if (!identity && (variant === "agent_path" || variant === "agent_body")) {
  console.error("Usage: node node_api_harness_real.cjs <iterations> <apiUrl> <variant> [identity]");
  process.exit(1);
}

const repoRoot = path.resolve(__dirname, "../..");
const { evaluatePolicy, loadPolicyPack } = require(path.join(repoRoot, "src/evaluator.js"));

const policyPack = loadPolicyPack("system.command.execute.v1");
const context = { tool: "system.command.execute", command: "ls" };

let passport = null;
if (variant === "passport_path" || variant === "passport_body") {
  const raw = fs.readFileSync(identity, "utf8");
  passport = JSON.parse(raw);
  if (!passport.agent_id && passport.passport_id) passport.agent_id = passport.passport_id;
}

const usePolicyInBody = variant === "agent_body" || variant === "passport_body";
const options = {
  apiUrl,
  policyInBody: usePolicyInBody,
};
if (variant === "agent_path" || variant === "agent_body") {
  options.agentId = identity;
} else {
  // passport_path | passport_body: send passport in body
  if (!passport) throw new Error("Passport required for " + variant);
}

const latencies = [];

(async () => {
  for (let i = 0; i < iterations; i++) {
    const start = performance.now();
    try {
      await evaluatePolicy(
        policyPack,
        variant.startsWith("passport_") ? passport : null,
        context,
        options
      );
    } catch (err) {
      console.error("Error:", err.message);
      process.exit(1);
    }
    latencies.push(performance.now() - start);
  }
  console.log(JSON.stringify(latencies));
})();
