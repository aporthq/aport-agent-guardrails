/**
 * Node API guardrail performance harness.
 * Mocks fetch; runs evaluatePolicy() N times and outputs JSON array of latencies (ms).
 * Usage: node tests/performance/node_api_harness.cjs <iterations> [apiUrl]
 * Output: one line JSON array of numbers (ms), e.g. [1.2, 0.9, ...]
 */
"use strict";

const iterations = Math.min(parseInt(process.argv[2], 10) || 50, 500);
const apiUrl = process.argv[3] || "https://api.aport.io";

const policyPack = { id: "system.command.execute.v1", requires_capabilities: ["system.command.execute"] };
const passport = { passport_id: "perf-p1", agent_id: "perf-a1", owner_id: "perf-o1" };
const context = { tool: "system.command.execute", command: "ls" };

const latencies = [];

globalThis.fetch = function () {
  return Promise.resolve({
    ok: true,
    json: () =>
      Promise.resolve({
        allow: true,
        decision_id: "perf-1",
        reasons: [{ message: "OK" }],
      }),
  });
};

const { evaluatePolicy } = require("../../src/evaluator.js");

(async () => {
  for (let i = 0; i < iterations; i++) {
    const start = performance.now();
    await evaluatePolicy(policyPack, passport, context, {
      apiUrl,
      policyInBody: false,
    });
    latencies.push(performance.now() - start);
  }
  // Output JSON array of latencies (ms) on one line for parsing
  console.log(JSON.stringify(latencies));
})();
