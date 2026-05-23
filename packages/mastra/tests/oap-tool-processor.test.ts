/**
 * Tests for OAPToolProcessor.
 */

import { describe, it, expect, beforeEach, jest } from '@jest/globals';
import { OAPToolProcessor } from '../src/oap-tool-processor.js';
import { OAPAuthorizationError } from '../src/errors.js';
import type { AgentContext } from '../src/types.js';

// Mock the core module
jest.mock('@aporthq/aport-agent-guardrails-core', () => ({
  Evaluator: jest.fn().mockImplementation(() => ({
    verifySync: jest.fn(),
  })),
  findConfigPath: jest.fn().mockReturnValue('/mock/config.yaml'),
  toolToPackId: jest.fn((name: string) => `pack:${name}`),
}));

import { Evaluator, toolToPackId } from '@aporthq/aport-agent-guardrails-core';

describe('OAPToolProcessor', () => {
  let processor: OAPToolProcessor;
  let mockContext: AgentContext;
  let mockEmit: jest.Mock;
  let mockVerifySync: jest.Mock;

  beforeEach(() => {
    jest.clearAllMocks();
    
    mockEmit = jest.fn();
    mockContext = {
      agentId: 'test-agent',
      agentName: 'Test Agent',
      runId: 'run-123',
      emit: mockEmit,
      get: jest.fn(),
      set: jest.fn(),
    };

    // Setup mock verifySync
    mockVerifySync = jest.fn();
    (Evaluator as unknown as jest.Mock).mockImplementation(() => ({
      verifySync: mockVerifySync,
    }));

    processor = new OAPToolProcessor('/test/policy.yaml');
  });

  describe('constructor', () => {
    it('should accept a string path', () => {
      const p = new OAPToolProcessor('/path/to/policy.yaml');
      expect(p.getConfig().policyPath).toBe('/path/to/policy.yaml');
    });

    it('should accept a config object', () => {
      const config = {
        policyPath: '/path/to/policy.yaml',
        framework: 'custom',
        failOpenWhenMissing: true,
      };
      const p = new OAPToolProcessor(config);
      expect(p.getConfig()).toMatchObject(config);
    });

    it('should use default framework value', () => {
      const p = new OAPToolProcessor({ policyPath: '/test.yaml' });
      expect(p.getConfig().framework).toBe('mastra');
    });
  });

  describe('beforeToolCall', () => {
    it('should allow tool calls when policy permits', async () => {
      mockVerifySync.mockReturnValue({ allow: true });

      await processor.beforeToolCall('web_search', { query: 'test' }, mockContext);

      expect(mockVerifySync).toHaveBeenCalledWith(
        {},
        { capability: 'pack:web_search' },
        expect.objectContaining({ tool: 'web_search', input: expect.any(String) })
      );
      expect(mockEmit).toHaveBeenCalledWith('oap:receipt', expect.objectContaining({
        allowed: true,
        tool: 'web_search',
        agent: 'test-agent',
      }));
    });

    it('should block tool calls when policy denies', async () => {
      mockVerifySync.mockReturnValue({
        allow: false,
        reasons: [{ message: 'Tool not allowed', code: 'policy.deny' }],
      });

      await expect(
        processor.beforeToolCall('bash', { command: 'rm -rf /' }, mockContext)
      ).rejects.toThrow(OAPAuthorizationError);

      expect(mockEmit).toHaveBeenCalledWith('oap:receipt', expect.objectContaining({
        allowed: false,
        tool: 'bash',
      }));
    });

    it('should include receipt ID in emitted events', async () => {
      mockVerifySync.mockReturnValue({ allow: true });

      await processor.beforeToolCall('read_file', { path: '/test.txt' }, mockContext);

      const receipt = mockEmit.mock.calls[0][1];
      expect(receipt.receiptId).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i);
      expect(receipt.timestamp).toMatch(/^\d{4}-\d{2}-\d{2}T/);
    });

    it('should call custom onReceipt handler if provided', async () => {
      const onReceipt = jest.fn();
      const customProcessor = new OAPToolProcessor({
        policyPath: '/test.yaml',
        onReceipt,
      });

      mockVerifySync.mockReturnValue({ allow: true });

      await customProcessor.beforeToolCall('tool', {}, mockContext);

      expect(onReceipt).toHaveBeenCalledWith(expect.objectContaining({
        allowed: true,
        tool: 'tool',
      }));
    });

    it('should handle string args', async () => {
      mockVerifySync.mockReturnValue({ allow: true });

      await processor.beforeToolCall('echo', 'hello world', mockContext);

      expect(mockVerifySync).toHaveBeenCalledWith(
        {},
        expect.any(Object),
        expect.objectContaining({ tool: 'echo', input: 'hello world' })
      );
    });

    it('should handle null args', async () => {
      mockVerifySync.mockReturnValue({ allow: true });

      await processor.beforeToolCall('noop', null, mockContext);

      expect(mockVerifySync).toHaveBeenCalledWith(
        {},
        expect.any(Object),
        expect.objectContaining({ tool: 'noop', input: 'null' })
      );
    });
  });

  describe('afterToolCall', () => {
    it('should complete without error', async () => {
      await expect(
        processor.afterToolCall('tool', {}, { result: 'ok' }, mockContext)
      ).resolves.not.toThrow();
    });
  });

  describe('clearCache', () => {
    it('should clear the policy cache', () => {
      // No public cache inspection, but we can verify it doesn't throw
      expect(() => processor.clearCache()).not.toThrow();
    });
  });

  describe('toolToPackId integration', () => {
    it('should convert tool names to pack IDs', async () => {
      mockVerifySync.mockReturnValue({ allow: true });
      (toolToPackId as jest.Mock).mockReturnValue('custom:pack:id');

      await processor.beforeToolCall('my_tool', {}, mockContext);

      expect(toolToPackId).toHaveBeenCalledWith('my_tool');
      expect(mockVerifySync).toHaveBeenCalledWith(
        {},
        { capability: 'custom:pack:id' },
        expect.any(Object)
      );
    });
  });
});