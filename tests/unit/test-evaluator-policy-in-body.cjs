/**
 * Unit test: Node evaluator with options.policyInBody sends POST to
 * /api/verify/policy/IN_BODY and includes body.policy (agent-passport API).
 */
"use strict";

const path = require("path");

const policyPack = { id: "custom.policy.v1", requires_capabilities: ["cap"] };
const passport = { passport_id: "p1", agent_id: "a1", owner_id: "o1" };
const context = { tool: "run" };

let capturedUrl;
let capturedBody;

const originalFetch = globalThis.fetch;
const originalHookFramework = process.env.APORT_HOOK_FRAMEWORK;
process.env.APORT_HOOK_FRAMEWORK = "cursor";
globalThis.fetch = function (url, options) {
  capturedUrl = url;
  capturedBody = options && options.body ? JSON.parse(options.body) : null;
  return Promise.resolve({
    ok: true,
    json: () => Promise.resolve({ allow: true, reasons: [] }),
  });
};

const { evaluatePolicy } = require("../../src/evaluator.js");

(async () => {
  try {
    await evaluatePolicy(policyPack, passport, context, {
      apiUrl: "https://example.com",
      policyInBody: true,
    });

    if (!capturedUrl.endsWith("/api/verify/policy/IN_BODY")) {
      console.error("FAIL: expected URL to end with /api/verify/policy/IN_BODY, got", capturedUrl);
      process.exit(1);
    }
    if (!capturedBody || !capturedBody.policy || capturedBody.policy.id !== policyPack.id) {
      console.error("FAIL: expected body.policy to be the policy pack, got", capturedBody && capturedBody.policy);
      process.exit(1);
    }
    if (capturedBody.runtime?.enforcement_mode !== "enforce" || capturedBody.runtime?.harness !== "cursor") {
      console.error("FAIL: expected runtime enforcement metadata, got", capturedBody && capturedBody.runtime);
      process.exit(1);
    }
    console.log("OK: policyInBody sends IN_BODY and body.policy");
  } finally {
    globalThis.fetch = originalFetch;
    if (originalHookFramework === undefined) {
      delete process.env.APORT_HOOK_FRAMEWORK;
    } else {
      process.env.APORT_HOOK_FRAMEWORK = originalHookFramework;
    }
  }
})();
