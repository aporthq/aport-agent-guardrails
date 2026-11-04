'use strict';

const { validateHandoff, serializeReport, serializeTestResult } = require('./contract');

function handoffFor(binding, origin) {
  const base = `${origin}/api/agent-installations/${binding.installation_id}`;
  return { schema_version: 'agent-installation-handoff/v1', ...binding,
    reporter_endpoint: `${base}/reports`, test_result_endpoint: `${base}/tests/{test_id}/results`,
    token_presentation: 'Authorization: Bearer <reporter_token>' };
}

// The only HTTP implementation. Both the durable worker and the compatibility
// in-memory reporter use this owner. Never follow redirects or log responses.
async function deliver(binding, origin, value, testId, key, options = {}) {
  validateHandoff(handoffFor(binding, origin), origin);
  if (value.source_id !== binding.installation_id || !/^[A-Za-z0-9_-]{8,128}$/.test(key) ||
      (testId !== undefined && !/^ait_[A-Za-z0-9_-]{1,100}$/.test(testId))) throw new TypeError('Invalid reporting scope');
  const body = testId === undefined ? serializeReport(value) : serializeTestResult(value);
  const controller = new AbortController();
  let timer;
  try {
    return await Promise.race([(async () => {
      const response = await (options.fetch || globalThis.fetch)(`${origin}/api/agent-installations/${binding.installation_id}${testId === undefined ? '/reports' : `/tests/${testId}/results`}`, {
        method: 'POST', redirect: 'error', signal: controller.signal,
        headers: { Authorization: `Bearer ${binding.reporter_token}`, 'Content-Type': 'application/json', 'Idempotency-Key': key }, body
      });
      if (!response || response.status < 200 || response.status >= 300) {
        try { await response?.body?.cancel(); } catch { /* Ignore server content. */ }
        return { accepted: false, retry: !response || response.status === 408 || response.status === 429 || response.status >= 500 };
      }
      const reader = response.body?.getReader();
      if (!reader) throw Error('Invalid response');
      const chunks = []; let bytes = 0;
      try {
        while (true) {
          const part = await reader.read();
          if (part.done) break;
          bytes += part.value.byteLength;
          if (bytes > 8192) { controller.abort(); throw Error('Oversized response'); }
          chunks.push(Buffer.from(part.value));
        }
      } finally { reader.releaseLock(); }
      const parsed = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      if (testId === undefined ? parsed?.event_id !== value.event_id || parsed.accepted !== value.reports.length
        : parsed?.test_id !== testId || !['passed', 'failed'].includes(parsed.result)) throw Error('Unmatched response');
      return { accepted: true, retry: false };
    })(), new Promise(resolve => {
      timer = setTimeout(() => { controller.abort(); resolve({ accepted: false, retry: true }); }, options.timeoutMs || 3000);
    })]);
  } catch { return { accepted: false, retry: true }; }
  finally { clearTimeout(timer); }
}
module.exports = { deliver, handoffFor };
