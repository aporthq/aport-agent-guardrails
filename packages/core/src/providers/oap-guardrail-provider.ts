/**
 * Generic OAP GuardrailProvider. Wraps the core Evaluator for any framework.
 *
 * Any framework that defines a GuardrailProvider interface with
 *   evaluate({ toolName, toolInput }) → { allow, reasons }
 * can use this. No framework-specific code.
 *
 * TypeScript equivalent of python/aport_guardrails/providers/generic.py.
 *
 * Usage:
 *   // OpenClaw config.yaml
 *   guardrails:
 *     enabled: true
 *     provider:
 *       use: "@aporthq/aport-agent-guardrails-core"
 *       config:
 *         framework: "openclaw"
 *
 *   // Programmatic
 *   import { OAPGuardrailProvider } from "@aporthq/aport-agent-guardrails-core";
 *   const provider = new OAPGuardrailProvider({ framework: "openclaw" });
 *   const decision = await provider.evaluate({ toolName: "exec", toolInput: { command: "ls" }, timestamp: "..." });
 */

import { Evaluator, toolToPackId } from "../core/evaluator.js";
import { findConfigPath, loadConfig } from "../core/config.js";

export interface OAPGuardrailProviderConfig {
  framework?: string;
  configPath?: string;
  enforcementMode?: "enforce" | "warn";
  enforcement_mode?: "enforce" | "warn";
}

export interface GuardrailRequest {
  toolName: string;
  toolInput: Record<string, unknown>;
  agentId?: string;
  sessionId?: string;
  runId?: string;
  toolCallId?: string;
  timestamp: string;
}

export interface GuardrailReason {
  code: string;
  message?: string;
}

export interface GuardrailDecision {
  allow: boolean;
  reasons: GuardrailReason[];
  policyId?: string;
  metadata?: Record<string, unknown>;
}

export class OAPGuardrailProvider {
  name = "aport";

  private evaluator: Evaluator;
  private enforcementMode: "enforce" | "warn";

  constructor(config: OAPGuardrailProviderConfig | Record<string, unknown> = {}) {
    const framework = (config as OAPGuardrailProviderConfig).framework ?? "generic";
    const configPath = (config as OAPGuardrailProviderConfig).configPath ?? findConfigPath(framework);
    const loadedConfig = configPath ? loadConfig(configPath) : {};
    this.enforcementMode = resolveEnforcementMode(
      (config as OAPGuardrailProviderConfig).enforcementMode ??
        (config as OAPGuardrailProviderConfig).enforcement_mode ??
        loadedConfig.enforcementMode ??
        loadedConfig.enforcement_mode,
    );
    this.evaluator = new Evaluator(configPath, framework);
  }

  /**
   * Build evaluator context from request.
   * The bash evaluator expects fields like .command at the top level.
   * toolToPackId maps the tool name to an OAP policy pack ID.
   */
  private buildContext(request: GuardrailRequest): Record<string, unknown> {
    const ctx: Record<string, unknown> = {
      tool: request.toolName,
      ...request.toolInput,
    };
    return ctx;
  }

  async evaluate(request: GuardrailRequest): Promise<GuardrailDecision> {
    const ctx = this.buildContext(request);
    const packId = toolToPackId(request.toolName);
    const decision = await this.evaluator.verify(
      {},
      { capability: packId },
      ctx,
    );
    return toDecision(decision, packId, this.enforcementMode);
  }

  evaluateSync(request: GuardrailRequest): GuardrailDecision {
    const ctx = this.buildContext(request);
    const packId = toolToPackId(request.toolName);
    const decision = this.evaluator.verifySync(
      {},
      { capability: packId },
      ctx,
    );
    return toDecision(decision, packId, this.enforcementMode);
  }

  async healthCheck(): Promise<{ ok: boolean; message?: string }> {
    return { ok: true, message: "OAP provider ready" };
  }
}

function toDecision(
  raw: { allow: boolean; reasons?: Array<{ code?: string; message?: string }> },
  packId: string,
  enforcementMode: "enforce" | "warn" = "enforce",
): GuardrailDecision {
  const reasons: GuardrailReason[] = (raw.reasons ?? []).map((r) => ({
    code: r.code ?? "oap.denied",
    message: r.message ?? "",
  }));
  if (reasons.length === 0) {
    reasons.push({ code: raw.allow ? "allowed" : "oap.denied" });
  }
  const originalAllow = raw.allow;
  const effectiveAllow = enforcementMode === "warn" ? true : originalAllow;
  const metadata =
    enforcementMode === "warn" || effectiveAllow !== originalAllow
      ? { enforcementMode, originalAllow }
      : undefined;
  return {
    allow: effectiveAllow,
    reasons,
    policyId: packId,
    ...(metadata && { metadata }),
  };
}

function resolveEnforcementMode(value: unknown): "enforce" | "warn" {
  const raw = String(
    value ??
      process.env.APORT_ENFORCEMENT_MODE ??
      process.env.APORT_ENFORCEMENT ??
      process.env.APORT_GUARDRAIL_ENFORCEMENT ??
      "",
  )
    .trim()
    .toLowerCase();
  if (["warn", "report-only", "report_only", "audit-only", "audit_only"].includes(raw)) {
    return "warn";
  }
  return "enforce";
}
