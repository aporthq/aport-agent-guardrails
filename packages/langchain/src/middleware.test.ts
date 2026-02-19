/**
 * Tests for APortGuardrailCallback: allow path does not throw; deny path throws GuardrailViolationError.
 */

import { Evaluator } from '@aporthq/aport-agent-guardrails-core';
import { APortGuardrailCallback, GuardrailViolationError } from './middleware.js';

jest.mock('@aporthq/aport-agent-guardrails-core', () => ({
  Evaluator: jest.fn().mockImplementation(() => ({ verify: jest.fn() })),
  toolToPackId: jest.fn((name: string) => 'system.command.execute.v1'),
}));

describe('APortGuardrailCallback', () => {
  const mockTool = { name: 'run_command', id: 'tool_1' };
  const mockInput = 'ls -la';

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('does not throw when decision.allow is true', async () => {
    (Evaluator as jest.Mock).mockImplementation(() => ({
      verify: jest.fn().mockResolvedValue({ allow: true }),
    }));
    const callback = new APortGuardrailCallback();
    await expect(
      callback.handleToolStart(
        mockTool as any,
        mockInput,
        'run-1',
        undefined,
        undefined,
        undefined,
        undefined
      )
    ).resolves.toBeUndefined();
  });

  it('throws GuardrailViolationError when decision.allow is false', async () => {
    (Evaluator as jest.Mock).mockImplementation(() => ({
      verify: jest.fn().mockResolvedValue({
        allow: false,
        reasons: [{ code: 'POLICY_DENIED', message: 'Tool not allowed by policy' }],
      }),
    }));
    const callback = new APortGuardrailCallback();
    await expect(
      callback.handleToolStart(
        mockTool as any,
        mockInput,
        'run-1',
        undefined,
        undefined,
        undefined,
        undefined
      )
    ).rejects.toThrow(GuardrailViolationError);
    await expect(
      callback.handleToolStart(
        mockTool as any,
        mockInput,
        'run-1',
        undefined,
        undefined,
        undefined,
        undefined
      )
    ).rejects.toMatchObject({
      message: 'Tool not allowed by policy',
      reasons: [{ code: 'POLICY_DENIED', message: 'Tool not allowed by policy' }],
    });
  });

  it('uses fallback message when reasons are empty', async () => {
    (Evaluator as jest.Mock).mockImplementation(() => ({
      verify: jest.fn().mockResolvedValue({ allow: false }),
    }));
    const callback = new APortGuardrailCallback();
    await expect(
      callback.handleToolStart(
        mockTool as any,
        mockInput,
        'run-1',
        undefined,
        undefined,
        undefined,
        undefined
      )
    ).rejects.toThrow('APort policy denied tool execution');
  });
});

describe('GuardrailViolationError', () => {
  it('has name GuardrailViolationError and optional reasons', () => {
    const err = new GuardrailViolationError('Denied', [
      { code: 'X', message: 'Y' },
    ]);
    expect(err.name).toBe('GuardrailViolationError');
    expect(err.message).toBe('Denied');
    expect(err.reasons).toEqual([{ code: 'X', message: 'Y' }]);
  });
});
