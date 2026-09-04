/**
 * Tests for OAPGuardrailProvider — the generic TypeScript provider.
 * Mirrors python/aport_guardrails/tests/test_generic_provider.py.
 */

import { OAPGuardrailProvider } from "./oap-guardrail-provider.js";
import type { GuardrailRequest, GuardrailDecision } from "./oap-guardrail-provider.js";

function makeRequest(toolName: string, toolInput: Record<string, unknown> = {}): GuardrailRequest {
  return { toolName, toolInput, timestamp: new Date().toISOString() };
}

describe("OAPGuardrailProvider", () => {
  it("has name 'aport'", () => {
    const provider = new OAPGuardrailProvider({ framework: "test" });
    expect(provider.name).toBe("aport");
  });

  it("evaluate returns a GuardrailDecision shape", async () => {
    const provider = new OAPGuardrailProvider({ framework: "nonexistent-framework" });
    const decision = await provider.evaluate(makeRequest("ls"));
    expect(typeof decision.allow).toBe("boolean");
    expect(Array.isArray(decision.reasons)).toBe(true);
    expect(decision.reasons.length).toBeGreaterThan(0);
    expect(typeof decision.reasons[0].code).toBe("string");
  });

  it("evaluateSync returns a GuardrailDecision shape", () => {
    const provider = new OAPGuardrailProvider({ framework: "nonexistent-framework" });
    const decision = provider.evaluateSync(makeRequest("ls"));
    expect(typeof decision.allow).toBe("boolean");
    expect(Array.isArray(decision.reasons)).toBe(true);
  });

  it("policyId is set to the mapped pack ID", async () => {
    const provider = new OAPGuardrailProvider({ framework: "nonexistent-framework" });
    const decision = await provider.evaluate(makeRequest("bash", { command: "ls" }));
    // bash maps to system.command.execute.v1 (or falls back)
    expect(decision.policyId).toBeTruthy();
  });

  it("healthCheck returns ok", async () => {
    const provider = new OAPGuardrailProvider();
    const health = await provider.healthCheck();
    expect(health.ok).toBe(true);
  });

  it("accepts empty config", () => {
    const provider = new OAPGuardrailProvider();
    expect(provider.name).toBe("aport");
  });

  it("accepts Record<string, unknown> config (framework loader compatibility)", () => {
    const provider = new OAPGuardrailProvider({ framework: "openclaw" } as Record<string, unknown>);
    expect(provider.name).toBe("aport");
  });

  it("keeps default enforcement fail-closed for denied decisions", () => {
    const provider = new OAPGuardrailProvider({ framework: "nonexistent-framework" });
    const decision = provider.evaluateSync(makeRequest("bash", { command: "rm -rf /tmp/aport-test" }));
    expect(decision.allow).toBe(false);
    expect(decision.metadata).toBeUndefined();
  });

  it("allows framework execution in warn mode while preserving original deny metadata", () => {
    const provider = new OAPGuardrailProvider({
      framework: "nonexistent-framework",
      enforcementMode: "warn",
    });
    const decision = provider.evaluateSync(makeRequest("bash", { command: "rm -rf /tmp/aport-test" }));
    expect(decision.allow).toBe(true);
    expect(decision.metadata).toMatchObject({
      enforcementMode: "warn",
      originalAllow: false,
    });
  });
});
