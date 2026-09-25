/**
 * Unit test: APORT_API_TIMEOUT that is not a usable number falls back to 15 s instead of making
 * AbortSignal.timeout throw (which denied every hosted evaluation with oap.evaluation_error).
 */
"use strict";
const assert = require("assert");
const path = require("path");
const { apiTimeoutMs } = require(path.join(__dirname, "..", "..", "src", "evaluator.js"));

assert.strictEqual(apiTimeoutMs(undefined), 15000);
assert.strictEqual(apiTimeoutMs(""), 15000);
assert.strictEqual(apiTimeoutMs("15s"), 15000, "a unit suffix is not a number");
assert.strictEqual(apiTimeoutMs("1.0001"), 1000, "fractional seconds round to whole milliseconds");
assert.strictEqual(apiTimeoutMs("0"), 15000, "zero is not a bound");
assert.strictEqual(apiTimeoutMs("-3"), 15000);
assert.strictEqual(apiTimeoutMs("45"), 45000);
for (const raw of ["15s", "1.0001", "NaN", "45"]) {
  assert.doesNotThrow(() => AbortSignal.timeout(apiTimeoutMs(raw)), `AbortSignal.timeout must accept the value for ${raw}`);
}
console.log("PASS: evaluator API timeout parsing");
