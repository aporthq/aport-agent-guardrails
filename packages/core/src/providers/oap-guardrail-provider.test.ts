/**
 * Tests for OAPGuardrailProvider — the generic TypeScript provider.
 * Mirrors python/aport_guardrails/tests/test_generic_provider.py.
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { OAPGuardrailProvider } from "./oap-guardrail-provider.js";
import type { GuardrailRequest, GuardrailDecision } from "./oap-guardrail-provider.js";

function makeRequest(toolName: string, toolInput: Record<string, unknown> = {}): GuardrailRequest {
  return { toolName, toolInput, timestamp: new Date().toISOString() };
}

function repoFile(...segments: string[]): string {
  for (const root of [process.cwd(), path.resolve(process.cwd(), "../.."), path.resolve(__dirname, "../../../..")]) {
    const candidate = path.join(root, ...segments);
    if (fs.existsSync(candidate)) return candidate;
  }
  return path.resolve(__dirname, "../../../..", ...segments);
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
    (provider as any).evaluator = {
      verifySync: () => ({
        allow: false,
        reasons: [{ code: "oap.command_not_allowed", message: "blocked by policy" }],
      }),
    };

    const decision = provider.evaluateSync(makeRequest("bash", { command: "rm -rf /tmp/aport-test" }));
    expect(decision.allow).toBe(true);
    expect(decision.metadata).toMatchObject({
      enforcementMode: "warn",
      originalAllow: false,
    });
  });

  it("keeps runtime failures blocking in warn mode", () => {
    const provider = new OAPGuardrailProvider({
      framework: "nonexistent-framework",
      enforcementMode: "warn",
    });
    (provider as any).evaluator = {
      verifySync: () => ({
        allow: false,
        reasons: [{ code: "oap.api_error", message: "API unavailable" }],
      }),
    };

    const decision = provider.evaluateSync(makeRequest("bash", { command: "ls" }));
    expect(decision.allow).toBe(false);
    expect(decision.metadata).toMatchObject({
      enforcementMode: "warn",
      originalAllow: false,
    });
  });

  it("keeps local MCP parser failures blocking in warn mode", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "aport-provider-mcp-"));
    try {
      const passportPath = path.join(tmpDir, "passport.json");
      const configPath = path.join(tmpDir, "config.json");
      fs.writeFileSync(
        passportPath,
        JSON.stringify({
          passport_id: "ap_mcp_parser_failure",
          agent_id: "ap_mcp_parser_failure",
          spec_version: "oap/1.0",
          owner_id: "test@example.com",
          assurance_level: "L2",
          status: "active",
          capabilities: [{ id: "mcp.tool.execute" }],
          limits: {},
          regions: ["US"],
          never_expires: true,
        }),
        "utf8",
      );
      fs.writeFileSync(
        configPath,
        JSON.stringify({
          mode: "local",
          framework: "generic",
          passport_path: passportPath,
          guardrail_script: repoFile("bin", "aport-guardrail-bash.sh"),
        }),
        "utf8",
      );

      const provider = new OAPGuardrailProvider({
        framework: "generic",
        configPath,
        enforcementMode: "warn",
      });
      const decision = provider.evaluateSync(
        makeRequest("mcp.github.issues", {
          server: "github\\evil",
          invalid_server: true,
          mcp_tool: "issues.list",
        }),
      );

      expect(decision.allow).toBe(false);
      expect(decision.policyId).toBe("mcp.tool.execute.v1");
      expect(decision.reasons[0].code).toBe("oap.invalid_mcp_server");
      expect(decision.metadata).toMatchObject({
        enforcementMode: "warn",
        originalAllow: false,
      });
    } finally {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  });

  it("allows framework execution in observe mode while preserving original deny metadata", () => {
    const provider = new OAPGuardrailProvider({
      framework: "nonexistent-framework",
      enforcementMode: "observe",
    });
    const decision = provider.evaluateSync(makeRequest("bash", { command: "rm -rf /tmp/aport-test" }));
    expect(decision.allow).toBe(true);
    expect(decision.metadata).toMatchObject({
      enforcementMode: "observe",
      originalAllow: false,
    });
  });

  it("reports explicit warn mode to hosted runtime metadata", async () => {
    const originalFetch = globalThis.fetch;
    let capturedBody: Record<string, unknown> | null = null;

    globalThis.fetch = (async (_url: string | URL | Request, init?: RequestInit) => {
      capturedBody = JSON.parse(String(init?.body ?? "{}")) as Record<string, unknown>;
      return {
        ok: true,
        status: 200,
        statusText: "OK",
        text: async () =>
          JSON.stringify({
            decision: {
              allow: false,
              reasons: [{ code: "oap.denied", message: "blocked" }],
            },
          }),
      } as Response;
    }) as typeof fetch;

    try {
      const provider = new OAPGuardrailProvider({
        framework: "generic",
        enforcementMode: "warn",
      });
      (provider as any).evaluator.cachedConfig = {
        mode: "api",
        agent_id: "ap_1234567890abcdef1234567890abcdef",
        enforcement_mode: "enforce",
      };

      const decision = await provider.evaluate(makeRequest("bash", { command: "sudo ls" }));

      expect(decision.allow).toBe(true);
      expect(decision.metadata).toMatchObject({
        enforcementMode: "warn",
        originalAllow: false,
      });
      const body = capturedBody as { runtime?: unknown } | null;
      expect(body?.runtime).toMatchObject({
        enforcement_mode: "warn",
        harness: "generic",
      });
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("reports explicit observe mode to hosted runtime metadata", async () => {
    const originalFetch = globalThis.fetch;
    let capturedBody: Record<string, unknown> | null = null;

    globalThis.fetch = (async (_url: string | URL | Request, init?: RequestInit) => {
      capturedBody = JSON.parse(String(init?.body ?? "{}")) as Record<string, unknown>;
      return {
        ok: true,
        status: 200,
        statusText: "OK",
        text: async () =>
          JSON.stringify({
            decision: {
              allow: false,
              reasons: [{ code: "oap.denied", message: "blocked" }],
            },
          }),
      } as Response;
    }) as typeof fetch;

    try {
      const provider = new OAPGuardrailProvider({
        framework: "generic",
        enforcementMode: "observe",
      });
      (provider as any).evaluator.cachedConfig = {
        mode: "api",
        agent_id: "ap_1234567890abcdef1234567890abcdef",
        enforcement_mode: "enforce",
      };

      const decision = await provider.evaluate(makeRequest("bash", { command: "sudo ls" }));

      expect(decision.allow).toBe(true);
      expect(decision.metadata).toMatchObject({
        enforcementMode: "observe",
        originalAllow: false,
      });
      const body = capturedBody as { runtime?: unknown } | null;
      expect(body?.runtime).toMatchObject({
        enforcement_mode: "observe",
        harness: "generic",
      });
    } finally {
      globalThis.fetch = originalFetch;
    }
  });
});
