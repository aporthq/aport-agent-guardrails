/**
 * Unit tests for AutoGen APortGuardedTool and guardFunction.
 * Mocks the core Evaluator so no APort server or passport is required.
 */

import { APortGuardedTool, guardFunction, GuardrailViolationError } from './middleware.js';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeMockEvaluator(allow: boolean, code = 'oap.denied', message = 'APort denied') {
  return {
    verify: jest.fn().mockResolvedValue({
      allow,
      reasons: allow ? undefined : [{ code, message }],
    }),
  };
}

function makeInnerTool(name = 'send_email') {
  return {
    name,
    description: `Mock tool: ${name}`,
    schema: {},
    run: jest.fn().mockResolvedValue('ok'),
    run_json: jest.fn().mockResolvedValue('ok'),
  };
}

// Patch the Evaluator in middleware module
jest.mock('@aporthq/aport-agent-guardrails-core', () => ({
  Evaluator: jest.fn(),
  toolToPackId: (name: string) => `oap.${name}`,
}));

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { Evaluator } = require('@aporthq/aport-agent-guardrails-core');

// ---------------------------------------------------------------------------
// APortGuardedTool
// ---------------------------------------------------------------------------

describe('APortGuardedTool', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('allow: run_json delegates to inner tool', async () => {
    Evaluator.mockImplementation(() => makeMockEvaluator(true));
    const inner = makeInnerTool('send_email');
    const guarded = new APortGuardedTool(inner);

    const result = await guarded.run_json({ recipient: 'user@example.com', body: 'Hello' });

    expect(result).toBe('ok');
    expect(inner.run_json).toHaveBeenCalledTimes(1);
  });

  it('deny: run_json throws GuardrailViolationError', async () => {
    Evaluator.mockImplementation(() =>
      makeMockEvaluator(false, 'oap.email_denied', 'Email sending denied')
    );
    const inner = makeInnerTool('send_email');
    const guarded = new APortGuardedTool(inner);

    await expect(guarded.run_json({ recipient: 'evil@example.com' })).rejects.toThrow(
      GuardrailViolationError
    );
    expect(inner.run_json).not.toHaveBeenCalled();
  });

  it('deny: error has correct code and message', async () => {
    Evaluator.mockImplementation(() =>
      makeMockEvaluator(false, 'oap.blocked', 'Blocked by policy')
    );
    const inner = makeInnerTool();
    const guarded = new APortGuardedTool(inner);

    try {
      await guarded.run_json({});
      fail('Expected GuardrailViolationError');
    } catch (err) {
      expect(err).toBeInstanceOf(GuardrailViolationError);
      expect((err as GuardrailViolationError).code).toBe('oap.blocked');
      expect((err as GuardrailViolationError).message).toContain('Blocked by policy');
    }
  });

  it('allow: run delegates to inner.run', async () => {
    Evaluator.mockImplementation(() => makeMockEvaluator(true));
    const inner = makeInnerTool('read_file');
    const guarded = new APortGuardedTool(inner);

    await guarded.run({ path: '/tmp/test.txt' });

    expect(inner.run).toHaveBeenCalledTimes(1);
  });

  it('deny: run throws GuardrailViolationError', async () => {
    Evaluator.mockImplementation(() => makeMockEvaluator(false));
    const inner = makeInnerTool();
    const guarded = new APortGuardedTool(inner);

    await expect(guarded.run({})).rejects.toThrow(GuardrailViolationError);
    expect(inner.run).not.toHaveBeenCalled();
  });

  it('proxies name, description, schema', () => {
    Evaluator.mockImplementation(() => makeMockEvaluator(true));
    const inner = makeInnerTool('list_files');
    (inner as Record<string, unknown>).schema = { type: 'object' };
    const guarded = new APortGuardedTool(inner);

    expect(guarded.name).toBe('list_files');
    expect(guarded.description).toBe('Mock tool: list_files');
    expect(guarded.schema).toEqual({ type: 'object' });
  });

  it('context includes tool name in verify call', async () => {
    const mockEval = makeMockEvaluator(true);
    Evaluator.mockImplementation(() => mockEval);
    const inner = makeInnerTool('call_api');
    const guarded = new APortGuardedTool(inner);

    await guarded.run_json({ url: 'https://example.com' });

    const callArgs = mockEval.verify.mock.calls[0];
    const context = callArgs[2];
    expect(context.tool).toBe('call_api');
    expect(context.input).toContain('example.com');
  });

  it('falls back to run when run_json not present on inner', async () => {
    Evaluator.mockImplementation(() => makeMockEvaluator(true));
    const inner = {
      name: 'no_run_json',
      description: 'No run_json',
      run: jest.fn().mockResolvedValue('fallback'),
    };
    const guarded = new APortGuardedTool(inner as never);
    const result = await guarded.run_json({});
    expect(result).toBe('fallback');
  });
});

// ---------------------------------------------------------------------------
// guardFunction
// ---------------------------------------------------------------------------

describe('guardFunction', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('allow: executes the wrapped function', async () => {
    Evaluator.mockImplementation(() => makeMockEvaluator(true));
    const fn = jest.fn().mockResolvedValue('result');
    Object.defineProperty(fn, 'name', { value: 'my_tool' });

    const guarded = guardFunction(fn);
    const result = await guarded({ query: 'test' });

    expect(result).toBe('result');
    expect(fn).toHaveBeenCalledWith({ query: 'test' });
  });

  it('deny: throws GuardrailViolationError without calling function', async () => {
    Evaluator.mockImplementation(() =>
      makeMockEvaluator(false, 'oap.fn_denied', 'Function call denied')
    );
    const fn = jest.fn().mockResolvedValue('result');
    Object.defineProperty(fn, 'name', { value: 'my_tool' });

    const guarded = guardFunction(fn);

    await expect(guarded({ query: 'evil' })).rejects.toThrow(GuardrailViolationError);
    expect(fn).not.toHaveBeenCalled();
  });

  it('preserves the original function name', () => {
    Evaluator.mockImplementation(() => makeMockEvaluator(true));

    async function sendEmail(args: { recipient: string }) {
      return `sent to ${args.recipient}`;
    }

    const guarded = guardFunction(sendEmail);
    expect(guarded.name).toBe('sendEmail');
  });

  it('context includes tool name from function name', async () => {
    const mockEval = makeMockEvaluator(true);
    Evaluator.mockImplementation(() => mockEval);

    async function writeFile(args: { path: string; content: string }) {
      return 'written';
    }

    const guarded = guardFunction(writeFile);
    await guarded({ path: '/tmp/out.txt', content: 'data' });

    const callArgs = mockEval.verify.mock.calls[0];
    const context = callArgs[2];
    expect(context.tool).toBe('writeFile');
  });
});
