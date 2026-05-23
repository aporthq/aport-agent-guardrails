/**
 * Integration tests for OAPToolProcessor with Mastra-like setup.
 */

import { describe, it, expect, beforeEach, jest } from '@jest/globals';
import { OAPToolProcessor } from '../src/oap-tool-processor.js';
import { OAPAuthorizationError } from '../src/errors.js';
import type { AgentContext } from '../src/types.js';

// These are higher-level tests that simulate real usage patterns

describe('OAPToolProcessor Integration', () => {
  let events: Array<{ name: string; payload: unknown }> = [];
  let mockContext: AgentContext;

  beforeEach(() => {
    events = [];
    mockContext = {
      agentId: 'integration-agent',
      agentName: 'Integration Test Agent',
      runId: 'run-' + Date.now(),
      threadId: 'thread-123',
      resourceId: 'res-456',
      emit: (name: string, payload: unknown) => {
        events.push({ name, payload });
      },
      get: jest.fn(),
      set: jest.fn(),
    };
  });

  describe('configuration patterns', () => {
    it('should work with minimal configuration (string path)', () => {
      const processor = new OAPToolProcessor('./policy.yaml');
      expect(processor.name).toBe('oap-tool-processor');
      expect(processor.getConfig().policyPath).toBe('./policy.yaml');
    });

    it('should work with full configuration object', () => {
      const processor = new OAPToolProcessor({
        policyPath: './custom-policy.yaml',
        framework: 'custom-mastra',
        failOpenWhenMissing: true,
        onReceipt: (receipt) => {
          console.log('Receipt:', receipt);
        },
      });

      const config = processor.getConfig();
      expect(config.policyPath).toBe('./custom-policy.yaml');
      expect(config.framework).toBe('custom-mastra');
      expect(config.failOpenWhenMissing).toBe(true);
      expect(typeof config.onReceipt).toBe('function');
    });
  });

  describe('event emission', () => {
    it('should emit oap:receipt events for allowed calls', async () => {
      const processor = new OAPToolProcessor('./policy.yaml');
      
      // Mock the evaluator internally
      // @ts-expect-error - accessing private for test
      processor.evaluator = {
        verifySync: () => ({ allow: true }),
      };

      await processor.beforeToolCall('allowed_tool', { arg: 'value' }, mockContext);

      const receiptEvents = events.filter(e => e.name === 'oap:receipt');
      expect(receiptEvents).toHaveLength(1);
      
      const receipt = receiptEvents[0].payload as { allowed: boolean; tool: string };
      expect(receipt.allowed).toBe(true);
      expect(receipt.tool).toBe('allowed_tool');
    });

    it('should emit oap:receipt events for denied calls', async () => {
      const processor = new OAPToolProcessor('./policy.yaml');
      
      // @ts-expect-error - accessing private for test
      processor.evaluator = {
        verifySync: () => ({
          allow: false,
          reasons: [{ message: 'Not authorized', code: 'auth.denied' }],
        }),
      };

      try {
        await processor.beforeToolCall('denied_tool', { arg: 'value' }, mockContext);
        fail('should have thrown');
      } catch (error) {
        // Expected
      }

      const receiptEvents = events.filter(e => e.name === 'oap:receipt');
      expect(receiptEvents).toHaveLength(1);
      
      const receipt = receiptEvents[0].payload as { allowed: boolean; reason?: string };
      expect(receipt.allowed).toBe(false);
      expect(receipt.reason).toBe('Not authorized');
    });
  });

  describe('receipt structure', () => {
    it('should include all required receipt fields', async () => {
      const processor = new OAPToolProcessor('./policy.yaml');
      
      // @ts-expect-error - accessing private for test
      processor.evaluator = {
        verifySync: () => ({ allow: true }),
      };

      await processor.beforeToolCall('test_tool', {}, mockContext);

      const receipt = events[0].payload as {
        receiptId: string;
        tool: string;
        agent: string;
        allowed: boolean;
        timestamp: string;
      };

      expect(receipt.receiptId).toBeDefined();
      expect(receipt.tool).toBe('test_tool');
      expect(receipt.agent).toBe('integration-agent');
      expect(receipt.allowed).toBe(true);
      expect(receipt.timestamp).toMatch(/^\d{4}-\d{2}-\d{2}T/);
    });
  });

  describe('error handling', () => {
    it('should throw OAPAuthorizationError with receipt on denial', async () => {
      const processor = new OAPToolProcessor('./policy.yaml');
      
      // @ts-expect-error - accessing private for test
      processor.evaluator = {
        verifySync: () => ({
          allow: false,
          reasons: [{ message: 'Security policy violation', code: 'security.violation' }],
        }),
      };

      let caughtError: OAPAuthorizationError | null = null;
      try {
        await processor.beforeToolCall('dangerous_tool', { cmd: 'rm -rf /' }, mockContext);
      } catch (error) {
        if (error instanceof OAPAuthorizationError) {
          caughtError = error;
        }
      }

      expect(caughtError).not.toBeNull();
      expect(caughtError?.toolName).toBe('dangerous_tool');
      expect(caughtError?.receipt).toBeDefined();
      expect(caughtError?.receipt.allowed).toBe(false);
      expect(caughtError?.isOAPError).toBe(true);
    });

    it('should include tool name in error message', async () => {
      const processor = new OAPToolProcessor('./policy.yaml');
      
      // @ts-expect-error - accessing private for test
      processor.evaluator = {
        verifySync: () => ({
          allow: false,
          reasons: [{ message: 'Blocked' }],
        }),
      };

      await expect(
        processor.beforeToolCall('blocked_tool', {}, mockContext)
      ).rejects.toThrow('blocked_tool');
    });
  });

  describe('multi-tool scenarios', () => {
    it('should handle multiple tool calls independently', async () => {
      const processor = new OAPToolProcessor('./policy.yaml');
      
      // @ts-expect-error - accessing private for test
      processor.evaluator = {
        verifySync: (_passport: unknown, _policy: unknown, context: { tool?: string }) => {
          // Allow read_file, deny bash
          return {
            allow: context.tool !== 'bash',
            reasons: context.tool === 'bash' ? [{ message: 'Dangerous tool' }] : undefined,
          };
        },
      };

      // First call - allowed
      await processor.beforeToolCall('read_file', { path: '/safe.txt' }, mockContext);
      expect(events).toHaveLength(1);
      expect((events[0].payload as { allowed: boolean }).allowed).toBe(true);

      // Second call - denied
      await expect(
        processor.beforeToolCall('bash', { cmd: 'dangerous' }, mockContext)
      ).rejects.toThrow(OAPAuthorizationError);
      expect(events).toHaveLength(2);
      expect((events[1].payload as { allowed: boolean }).allowed).toBe(false);

      // Third call - allowed again
      await processor.beforeToolCall('read_file', { path: '/another.txt' }, mockContext);
      expect(events).toHaveLength(3);
      expect((events[2].payload as { allowed: boolean }).allowed).toBe(true);
    });
  });
});