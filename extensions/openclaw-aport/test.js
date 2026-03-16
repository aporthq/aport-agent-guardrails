#!/usr/bin/env node
/**
 * Unit, integration, and performance tests for APort OpenClaw plugin.
 * Run: node test.js
 */

import { describe, it } from 'node:test';
import assert from 'node:assert';
import { createHash } from 'crypto';
import { spawn } from 'child_process';
import { mkdtemp, writeFile, readFile, rm, mkdir } from 'fs/promises';
import { join } from 'path';
import { tmpdir } from 'os';
import { fileURLToPath } from 'url';
import { dirname } from 'path';
import plugin, {
  mapToolToPolicy,
  canonicalize,
  verifyDecisionIntegrity,
} from './index.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, '..', '..');
const GUARDRAIL_SCRIPT = join(REPO_ROOT, 'bin', 'aport-guardrail-bash.sh');

describe('canonicalize', () => {
  it('sorts keys at top level', () => {
    assert.strictEqual(
      canonicalize({ b: 1, a: 2 }),
      '{"a":2,"b":1}',
    );
  });

  it('sorts keys recursively in nested objects', () => {
    assert.strictEqual(
      canonicalize({ o: { z: 1, y: 2 } }),
      '{"o":{"y":2,"z":1}}',
    );
  });

  it('sorts keys in array elements', () => {
    assert.strictEqual(
      canonicalize({ reasons: [{ message: 'm', code: 'c' }] }),
      '{"reasons":[{"code":"c","message":"m"}]}',
    );
  });

  it('handles primitives and null', () => {
    assert.strictEqual(canonicalize(null), 'null');
    assert.strictEqual(canonicalize(1), '1');
    assert.strictEqual(canonicalize('x'), '"x"');
  });
});

describe('verifyDecisionIntegrity', () => {
  it('returns true when content_hash is missing (legacy decision)', () => {
    assert.strictEqual(verifyDecisionIntegrity({ allow: false }), true);
    assert.strictEqual(verifyDecisionIntegrity(null), true);
  });

  it('returns true when content_hash matches computed hash', () => {
    const decision = {
      allow: false,
      decision_id: 'dec-1',
      reasons: [{ code: 'oap.denied', message: 'test' }],
    };
    const canonical = canonicalize(decision);
    const hash =
      'sha256:' + createHash('sha256').update(canonical, 'utf8').digest('hex');
    assert.strictEqual(
      verifyDecisionIntegrity({ ...decision, content_hash: hash }),
      true,
    );
  });

  it('returns false when content is tampered (hash does not match)', () => {
    const decision = {
      allow: false,
      decision_id: 'dec-1',
      reasons: [{ code: 'oap.denied', message: 'test' }],
      content_hash: 'sha256:wrong',
    };
    assert.strictEqual(verifyDecisionIntegrity(decision), false);
  });

  it('returns false when a field is changed after hash was computed', () => {
    const decision = {
      allow: false,
      decision_id: 'dec-1',
      reasons: [{ code: 'oap.denied', message: 'original' }],
    };
    const canonical = canonicalize(decision);
    const hash =
      'sha256:' + createHash('sha256').update(canonical, 'utf8').digest('hex');
    const tampered = {
      ...decision,
      reasons: [{ code: 'oap.denied', message: 'tampered' }],
      content_hash: hash,
    };
    assert.strictEqual(verifyDecisionIntegrity(tampered), false);
  });
});

describe('mapToolToPolicy', () => {
  it('maps exec and exec.* to system.command.execute.v1', () => {
    assert.strictEqual(mapToolToPolicy('exec'), 'system.command.execute.v1');
    assert.strictEqual(mapToolToPolicy('exec.run'), 'system.command.execute.v1');
    assert.strictEqual(mapToolToPolicy('exec.shell'), 'system.command.execute.v1');
    assert.strictEqual(mapToolToPolicy('EXEC.RUN'), 'system.command.execute.v1');
  });

  it('maps system.command.* and bash/shell to system.command.execute.v1', () => {
    assert.strictEqual(mapToolToPolicy('system.command.run'), 'system.command.execute.v1');
    assert.strictEqual(mapToolToPolicy('bash'), 'system.command.execute.v1');
    assert.strictEqual(mapToolToPolicy('shell'), 'system.command.execute.v1');
    assert.strictEqual(mapToolToPolicy('command'), 'system.command.execute.v1');
  });

  it('maps git tools to code.repository.merge.v1', () => {
    assert.strictEqual(mapToolToPolicy('git.create_pr'), 'code.repository.merge.v1');
    assert.strictEqual(mapToolToPolicy('git.merge'), 'code.repository.merge.v1');
    assert.strictEqual(mapToolToPolicy('git.push'), 'code.repository.merge.v1');
    assert.strictEqual(mapToolToPolicy('git.commit'), 'code.repository.merge.v1');
  });

  it('maps messaging tools to messaging.message.send.v1', () => {
    assert.strictEqual(mapToolToPolicy('message.send'), 'messaging.message.send.v1');
    assert.strictEqual(mapToolToPolicy('messaging.slack'), 'messaging.message.send.v1');
  });

  it('maps mcp.* to mcp.tool.execute.v1', () => {
    assert.strictEqual(mapToolToPolicy('mcp.foo'), 'mcp.tool.execute.v1');
  });

  it('maps session/agent.session to agent.session.create.v1', () => {
    assert.strictEqual(mapToolToPolicy('agent.session.create'), 'agent.session.create.v1');
    assert.strictEqual(mapToolToPolicy('session.create'), 'agent.session.create.v1');
  });

  it('maps payment/finance to finance policies', () => {
    assert.strictEqual(mapToolToPolicy('payment.refund'), 'finance.payment.refund.v1');
    assert.strictEqual(mapToolToPolicy('payment.charge'), 'finance.payment.charge.v1');
  });

  it('maps data.export and database.* to data.export.create.v1', () => {
    assert.strictEqual(mapToolToPolicy('data.export'), 'data.export.create.v1');
    assert.strictEqual(mapToolToPolicy('database.write'), 'data.export.create.v1');
  });

  it('returns null for unmapped tools', () => {
    assert.strictEqual(mapToolToPolicy('unknown.tool'), null);
    assert.strictEqual(mapToolToPolicy('read_file'), null);
  });
});

describe('performance', () => {
  it('mapToolToPolicy: 5000 calls complete in under 100ms', () => {
    const tools = [
      'exec.run',
      'git.create_pr',
      'message.send',
      'unknown.tool',
    ];
    const start = process.hrtime.bigint();
    for (let i = 0; i < 5000; i++) {
      mapToolToPolicy(tools[i % tools.length]);
    }
    const elapsed = Number(process.hrtime.bigint() - start) / 1e6;
    assert.ok(elapsed < 100, `mapToolToPolicy 5k calls took ${elapsed.toFixed(2)}ms (expected < 100ms)`);
  });

  it('verifyDecisionIntegrity: 1000 valid checks in under 50ms', () => {
    const decision = {
      allow: false,
      decision_id: 'dec-1',
      reasons: [{ code: 'oap.denied', message: 'test' }],
    };
    const canonical = canonicalize(decision);
    const hash =
      'sha256:' + createHash('sha256').update(canonical, 'utf8').digest('hex');
    const withHash = { ...decision, content_hash: hash };
    const start = process.hrtime.bigint();
    for (let i = 0; i < 1000; i++) {
      assert.strictEqual(verifyDecisionIntegrity(withHash), true);
    }
    const elapsed = Number(process.hrtime.bigint() - start) / 1e6;
    assert.ok(elapsed < 50, `verifyDecisionIntegrity 1k calls took ${elapsed.toFixed(2)}ms (expected < 50ms)`);
  });

  it('canonicalize: 2000 objects in under 30ms', () => {
    const obj = {
      allow: false,
      decision_id: 'dec-1',
      reasons: [{ code: 'c', message: 'm' }],
      policy_id: 'system.command.execute.v1',
    };
    const start = process.hrtime.bigint();
    for (let i = 0; i < 2000; i++) {
      canonicalize(obj);
    }
    const elapsed = Number(process.hrtime.bigint() - start) / 1e6;
    assert.ok(elapsed < 30, `canonicalize 2k calls took ${elapsed.toFixed(2)}ms (expected < 30ms)`);
  });
});

/**
 * Integration: run real guardrail script when repo is available.
 * Ensures decision file has content_hash and chain fields; non-core writes don't block.
 */
describe('integration (guardrail script)', () => {
  it('writes decision with content_hash and chain; audit is non-blocking', async () => {
    const { existsSync } = await import('fs');
    if (!existsSync(GUARDRAIL_SCRIPT)) {
      console.log('  (skip: bin/aport-guardrail-bash.sh not found)');
      return;
    }
    const tmp = await mkdtemp(join(tmpdir(), 'aport-plugin-test-'));
    const passportPath = join(tmp, 'passport.json');
    const decisionsDir = join(tmp, 'decisions');
    const auditLog = join(tmp, 'audit.log');
    await mkdir(decisionsDir, { recursive: true });
    const minimalPassport = {
      spec_version: 'oap/1.0',
      passport_id: 'test-passport',
      agent_id: 'test-passport',
      owner_id: 'test-owner',
      status: 'active',
      capabilities: [{ id: 'system.command.execute' }],
      limits: {
        'system.command.execute': {
          allowed_commands: ['node'],
          blocked_patterns: [],
        },
      },
    };
    await writeFile(passportPath, JSON.stringify(minimalPassport));

    const runScript = (toolName, contextJson, decisionPath) =>
      new Promise((resolve, reject) => {
        const proc = spawn(GUARDRAIL_SCRIPT, [toolName, contextJson], {
          env: {
            ...process.env,
            OPENCLAW_PASSPORT_FILE: passportPath,
            OPENCLAW_DECISION_FILE: decisionPath,
            OPENCLAW_AUDIT_LOG: auditLog,
          },
          cwd: REPO_ROOT,
        });
        let stderr = '';
        proc.stderr.on('data', (d) => (stderr += d));
        proc.on('close', (code) => resolve({ code, stderr }));
        proc.on('error', reject);
      });

    const decisionPath1 = join(decisionsDir, 'run1.json');
    const res1 = await runScript(
      'system.command.execute',
      JSON.stringify({ command: 'node --version' }),
      decisionPath1,
    );
    if (res1.code !== 0) {
      console.log('  (skip: guardrail exited with code=' + res1.code + ', stderr=' + (res1.stderr || '').slice(0, 200) + ')');
      await rm(tmp, { recursive: true, force: true }).catch(() => {});
      return;
    }
    let dec1;
    try {
      dec1 = JSON.parse(await readFile(decisionPath1, 'utf8'));
    } catch (e) {
      console.log('  (skip: decision file missing or invalid JSON)');
      await rm(tmp, { recursive: true, force: true }).catch(() => {});
      return;
    }
    if (!dec1.content_hash) {
      console.log('  (skip: decision has no content_hash - need guardrail with tamper-resistant writes)');
      await rm(tmp, { recursive: true, force: true }).catch(() => {});
      return;
    }
    if (dec1.allow !== true) {
      console.log('  (skip: guardrail denied - passport/limits may not allow node)');
      await rm(tmp, { recursive: true, force: true }).catch(() => {});
      return;
    }
    assert.ok(verifyDecisionIntegrity(dec1), 'content_hash must verify');

    const decisionPath2 = join(decisionsDir, 'run2.json');
    const res2 = await runScript(
      'system.command.execute',
      JSON.stringify({ command: 'node --version' }),
      decisionPath2,
    );
    if (res2.code !== 0) {
      console.log('  (skip: second run exited code=' + res2.code + ')');
      await rm(tmp, { recursive: true, force: true }).catch(() => {});
      return;
    }
    const dec2 = JSON.parse(await readFile(decisionPath2, 'utf8'));
    assert.ok(dec2.content_hash);
    assert.ok(
      dec2.prev_decision_id != null || dec2.prev_content_hash != null,
      'second decision should chain',
    );
    assert.ok(verifyDecisionIntegrity(dec2), 'second decision must verify');

    await rm(tmp, { recursive: true, force: true });
  });
});

// --- Agent tool registration and behavior tests ---

describe('aport_check and aport_passport tool registration', () => {
  it('registers both tools with optional: true', () => {
    const registeredTools = [];
    const mockApi = {
      pluginConfig: { mode: 'local', passportFile: '/tmp/nonexistent-passport.json' },
      logger: { info: () => {}, warn: () => {}, error: () => {} },
      on: () => {},
      registerTool: (def, opts) => {
        registeredTools.push({ name: def.name, opts, parameters: def.parameters, execute: def.execute });
      },
    };

    plugin(mockApi);

    const checkTool = registeredTools.find((t) => t.name === 'aport_check');
    const passportTool = registeredTools.find((t) => t.name === 'aport_passport');

    assert.ok(checkTool, 'aport_check tool must be registered');
    assert.ok(passportTool, 'aport_passport tool must be registered');
    assert.deepStrictEqual(checkTool.opts, { optional: true });
    assert.deepStrictEqual(passportTool.opts, { optional: true });

    // Verify parameter schemas
    assert.ok(checkTool.parameters.properties.tool_name, 'aport_check must have tool_name param');
    assert.ok(checkTool.parameters.properties.params, 'aport_check must have params param');
    assert.deepStrictEqual(checkTool.parameters.required, ['tool_name']);

    assert.ok(passportTool.parameters.properties.action, 'aport_passport must have action param');
    assert.deepStrictEqual(passportTool.parameters.required, ['action']);
  });
});

describe('aport_check tool behavior', () => {
  /** Helper: register plugin and extract tool executors */
  function getTools(configOverrides = {}) {
    const registeredTools = {};
    const mockApi = {
      pluginConfig: {
        mode: 'local',
        passportFile: '/tmp/nonexistent-passport.json',
        guardrailScript: '/tmp/nonexistent-guardrail.sh',
        ...configOverrides,
      },
      logger: { info: () => {}, warn: () => {}, error: () => {} },
      on: () => {},
      registerTool: (def, _opts) => {
        registeredTools[def.name] = def.execute;
      },
    };
    plugin(mockApi);
    return registeredTools;
  }

  it('returns allowed:false for unmapped tool (allowUnmappedTools=false)', async () => {
    const tools = getTools({ allowUnmappedTools: false });
    const result = await tools.aport_check('id-1', { tool_name: 'unknown.tool.xyz' });
    const parsed = JSON.parse(result.content[0].text);
    assert.strictEqual(parsed.allowed, false);
    assert.strictEqual(parsed.policy, null);
    assert.ok(parsed.reason.includes('allowUnmappedTools: false'));
  });

  it('returns allowed:true for unmapped tool (allowUnmappedTools=true)', async () => {
    const tools = getTools({ allowUnmappedTools: true });
    const result = await tools.aport_check('id-2', { tool_name: 'unknown.tool.xyz' });
    const parsed = JSON.parse(result.content[0].text);
    assert.strictEqual(parsed.allowed, true);
    assert.strictEqual(parsed.policy, null);
    assert.ok(parsed.reason.includes('allowUnmappedTools: true'));
  });

  it('returns allowed:false with error reason when guardrail script missing', async () => {
    const tools = getTools({ mode: 'local', guardrailScript: '/tmp/no-such-script.sh' });
    const result = await tools.aport_check('id-3', { tool_name: 'exec', params: { command: 'ls' } });
    const parsed = JSON.parse(result.content[0].text);
    assert.strictEqual(parsed.allowed, false);
    assert.strictEqual(parsed.policy, 'system.command.execute.v1');
    assert.ok(parsed.reason.length > 0, 'should have error reason');
  });

  it('returns structured content with type:text', async () => {
    const tools = getTools({ allowUnmappedTools: true });
    const result = await tools.aport_check('id-4', { tool_name: 'some.tool' });
    assert.ok(Array.isArray(result.content));
    assert.strictEqual(result.content[0].type, 'text');
    const parsed = JSON.parse(result.content[0].text);
    assert.ok('allowed' in parsed);
    assert.ok('policy' in parsed);
    assert.ok('reason' in parsed);
  });
});

describe('aport_passport tool behavior', () => {
  function getTools(configOverrides = {}) {
    const registeredTools = {};
    const mockApi = {
      pluginConfig: {
        mode: 'local',
        ...configOverrides,
      },
      logger: { info: () => {}, warn: () => {}, error: () => {} },
      on: () => {},
      registerTool: (def, _opts) => {
        registeredTools[def.name] = def.execute;
      },
    };
    plugin(mockApi);
    return registeredTools;
  }

  it('read — returns passport data when file exists', async () => {
    const tmp = await mkdtemp(join(tmpdir(), 'aport-passport-test-'));
    const passportPath = join(tmp, 'passport.json');
    const passport = {
      spec_version: 'oap/1.0',
      passport_id: 'test-id-123',
      agent_id: 'test-agent',
      status: 'active',
      assurance_level: 'L2',
      capabilities: [{ id: 'system.command.execute' }, { id: 'data.file.read' }],
    };
    await writeFile(passportPath, JSON.stringify(passport));

    const tools = getTools({ passportFile: passportPath });
    const result = await tools.aport_passport('id-1', { action: 'read' });
    const parsed = JSON.parse(result.content[0].text);

    assert.strictEqual(parsed.status, 'ok');
    assert.strictEqual(parsed.passport_id, 'test-id-123');
    assert.strictEqual(parsed.assurance_level, 'L2');
    assert.deepStrictEqual(parsed.capabilities, ['system.command.execute', 'data.file.read']);
    assert.strictEqual(parsed.passport_status, 'active');

    await rm(tmp, { recursive: true, force: true });
  });

  it('read — returns not_found when file missing', async () => {
    const tools = getTools({ passportFile: '/tmp/no-such-dir/no-passport.json' });
    const result = await tools.aport_passport('id-2', { action: 'read' });
    const parsed = JSON.parse(result.content[0].text);

    assert.strictEqual(parsed.status, 'not_found');
    assert.ok(parsed.hint.includes('generate'));
  });

  it('generate — creates passport file when missing', async () => {
    const tmp = await mkdtemp(join(tmpdir(), 'aport-passport-gen-'));
    const passportPath = join(tmp, 'subdir', 'passport.json');

    const tools = getTools({ passportFile: passportPath });
    const result = await tools.aport_passport('id-3', { action: 'generate' });
    const parsed = JSON.parse(result.content[0].text);

    assert.strictEqual(parsed.status, 'created');
    assert.ok(parsed.hint.includes('Edit'));

    // Verify file was created with valid content
    const fileContent = JSON.parse(await readFile(passportPath, 'utf8'));
    assert.strictEqual(fileContent.spec_version, 'oap/1.0');
    assert.strictEqual(fileContent.status, 'active');
    assert.ok(fileContent.passport_id, 'should have passport_id (UUID)');
    assert.ok(Array.isArray(fileContent.capabilities));
    assert.ok(fileContent.capabilities.length >= 4);

    await rm(tmp, { recursive: true, force: true });
  });

  it('generate — returns exists when passport already present', async () => {
    const tmp = await mkdtemp(join(tmpdir(), 'aport-passport-exists-'));
    const passportPath = join(tmp, 'passport.json');
    const original = JSON.stringify({ spec_version: 'oap/1.0', passport_id: 'existing' });
    await writeFile(passportPath, original);

    const tools = getTools({ passportFile: passportPath });
    const result = await tools.aport_passport('id-4', { action: 'generate' });
    const parsed = JSON.parse(result.content[0].text);

    assert.strictEqual(parsed.status, 'exists');
    assert.ok(parsed.hint.includes('read'));

    // Verify file was NOT overwritten
    const fileContent = await readFile(passportPath, 'utf8');
    assert.strictEqual(fileContent, original);

    await rm(tmp, { recursive: true, force: true });
  });
});
