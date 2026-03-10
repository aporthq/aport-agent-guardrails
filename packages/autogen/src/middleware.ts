/**
 * AutoGen-compatible guardrail hook: wrap tool functions with APort pre-action
 * verification.  Designed for AutoGen 0.4.x-style tool interfaces and any
 * TypeScript agent framework that exposes callable tools.
 *
 * Two entry points:
 *   - `APortGuardedTool`: wraps an AutoGen-style tool object (name + run).
 *   - `guardFunction`: wraps a plain async function with APort verification.
 */

import { Evaluator, toolToPackId } from "@aporthq/aport-agent-guardrails-core";

/** Thrown when APort denies a tool call. */
export class GuardrailViolationError extends Error {
  readonly code: string;
  readonly reasons?: Array<{ code?: string; message?: string }>;

  constructor(
    message: string,
    code: string,
    reasons?: Array<{ code?: string; message?: string }>
  ) {
    super(message);
    this.name = "GuardrailViolationError";
    this.code = code;
    this.reasons = reasons;
  }
}

/** Minimal AutoGen-style tool interface (duck-typed). */
export interface AutoGenTool<TArgs = Record<string, unknown>, TResult = unknown> {
  readonly name: string;
  readonly description: string;
  readonly schema?: unknown;
  run(args: TArgs, cancellationToken?: unknown): Promise<TResult>;
  run_json?(args: TArgs, cancellationToken?: unknown): Promise<TResult>;
}

export interface APortGuardedToolOptions {
  /** Optional path to APort config YAML. Defaults to auto-detect. */
  configPath?: string | null;
  /** Framework key for config lookup. Default: "autogen". */
  framework?: string;
}

/**
 * Wraps an AutoGen-style tool with APort pre-action authorization.
 * Intercepts `run_json` (if present) or `run` before delegating to the inner tool.
 *
 * @example
 * ```ts
 * const guarded = new APortGuardedTool(myFunctionTool);
 * const result = await guarded.run({ recipient: "test@example.com" });
 * ```
 */
export class APortGuardedTool<
  TArgs extends Record<string, unknown> = Record<string, unknown>,
  TResult = unknown
> implements AutoGenTool<TArgs, TResult> {
  private readonly inner: AutoGenTool<TArgs, TResult>;
  private readonly evaluator: Evaluator;

  constructor(
    inner: AutoGenTool<TArgs, TResult>,
    options: APortGuardedToolOptions = {}
  ) {
    this.inner = inner;
    this.evaluator = new Evaluator(
      options.configPath ?? null,
      options.framework ?? "autogen"
    );
  }

  get name(): string {
    return this.inner.name;
  }

  get description(): string {
    return this.inner.description;
  }

  get schema(): unknown {
    return (this.inner as { schema?: unknown }).schema;
  }

  private async _checkPolicy(args: TArgs): Promise<void> {
    const toolName = this.name;
    const packId = toolToPackId(toolName);
    const inputStr = JSON.stringify(args);

    const decision = await this.evaluator.verify(
      {},
      { capability: packId },
      { tool: toolName, input: inputStr, ...args }
    );

    if (!decision.allow) {
      const msg =
        decision.reasons?.[0]?.message ??
        "APort policy denied tool execution";
      const code = decision.reasons?.[0]?.code ?? "oap.denied";
      console.warn("[APort] Denied:", toolName, decision.reasons ?? msg);
      throw new GuardrailViolationError(msg, code, decision.reasons);
    }
  }

  async run_json(
    args: TArgs,
    cancellationToken?: unknown
  ): Promise<TResult> {
    await this._checkPolicy(args);
    if (typeof this.inner.run_json === "function") {
      return this.inner.run_json(args, cancellationToken);
    }
    return this.inner.run(args, cancellationToken);
  }

  async run(args: TArgs, cancellationToken?: unknown): Promise<TResult> {
    await this._checkPolicy(args);
    return this.inner.run(args, cancellationToken);
  }
}

/**
 * Wrap a plain async function with APort pre-action verification.
 * The function name is used as the tool name for policy lookup.
 *
 * @example
 * ```ts
 * const guardedSendEmail = guardFunction(sendEmail);
 * await guardedSendEmail({ recipient: "user@example.com", body: "Hello" });
 * ```
 */
export function guardFunction<TArgs extends Record<string, unknown>, TResult>(
  fn: (args: TArgs) => Promise<TResult>,
  options: APortGuardedToolOptions = {}
): (args: TArgs) => Promise<TResult> {
  const toolName = fn.name || "unknown_tool";
  const evaluator = new Evaluator(
    options.configPath ?? null,
    options.framework ?? "autogen"
  );

  const guarded = async (args: TArgs): Promise<TResult> => {
    const packId = toolToPackId(toolName);
    const inputStr = JSON.stringify(args);

    const decision = await evaluator.verify(
      {},
      { capability: packId },
      { tool: toolName, input: inputStr, ...args }
    );

    if (!decision.allow) {
      const msg =
        decision.reasons?.[0]?.message ?? "APort policy denied tool execution";
      const code = decision.reasons?.[0]?.code ?? "oap.denied";
      console.warn("[APort] Denied:", toolName, decision.reasons ?? msg);
      throw new GuardrailViolationError(msg, code, decision.reasons);
    }

    return fn(args);
  };

  Object.defineProperty(guarded, "name", { value: toolName });
  return guarded;
}
