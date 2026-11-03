'use strict';

const { randomUUID } = require('node:crypto');
const { validateHandoff, serializeReport, serializeTestResult } = require('./contract');

// In-memory best-effort transport. No framework invokes this yet; callers must
// retain their existing enforcement result regardless of reporting outcomes.
class InstallationReporter {
  #installationId; #endpoint; #token; #fetch; #queue = []; #dropped = 0;
  #state = 'unverified'; #running = false; #maxQueue; #maxAttempts; #timeoutMs; #maxAgeMs;

  constructor(handoff, origin, options = {}) {
    const binding = validateHandoff(handoff, origin);
    this.#installationId = binding.installation_id;
    this.#endpoint = `${origin}/api/agent-installations/${binding.installation_id}`;
    this.#token = binding.reporter_token;
    this.#fetch = options.fetch || globalThis.fetch;
    if (typeof this.#fetch !== 'function') throw new TypeError('Reporting transport unavailable');
    const limit = (value, maximum) => {
      if (value === undefined) return maximum;
      if (!Number.isInteger(value) || value < 1 || value > maximum) throw new TypeError('Invalid reporting limit');
      return value;
    };
    this.#maxQueue = limit(options.maxQueue, 100);
    this.#maxAttempts = limit(options.maxAttempts, 3);
    this.#timeoutMs = limit(options.timeoutMs, 3000);
    this.#maxAgeMs = limit(options.maxAgeMs, 60000);
  }

  enqueueReport(value) {
    const body = serializeReport(value);
    if (value.source_id !== this.#installationId) throw new TypeError('Invalid installation reporting scope');
    this.#enqueue('/reports', body, { eventId: value.event_id, count: value.reports.length });
  }

  enqueueTestResult(testId, value) {
    if (typeof testId !== 'string' || testId.match(/^ait_[A-Za-z0-9_-]{1,100}$/)?.[0] !== testId) throw new TypeError('Invalid installation test ID');
    const body = serializeTestResult(value);
    if (value.source_id !== this.#installationId) throw new TypeError('Invalid installation reporting scope');
    this.#enqueue(`/tests/${testId}/results`, body, { testId });
  }

  #enqueue(path, body, expected) {
    if (this.#queue.length === this.#maxQueue) { this.#queue.shift(); this.#dropped++; this.#state = 'unresolved'; }
    this.#queue.push({ path, body, expected, key: randomUUID(), created: Date.now(), attempts: 0 });
    this.#schedule();
  }

  status() { return { state: this.#state, queued: this.#queue.length, dropped: this.#dropped }; }

  #schedule(delay = 0) {
    if (this.#running) return;
    this.#running = true;
    const timer = setTimeout(() => { this.#drain().catch(() => {
      this.#state = 'unresolved'; this.#dropped++; this.#running = false;
      if (this.#queue.length) this.#schedule();
    }); }, delay);
    timer.unref();
  }

  async #drain() {
    while (this.#queue.length) {
      const item = this.#queue.shift();
      if (Date.now() - item.created >= this.#maxAgeMs) { this.#dropped++; this.#state = 'unresolved'; continue; }
      item.attempts++;
      const controller = new AbortController();
      let timer;
      try {
        const timeout = new Promise((_, reject) => { timer = setTimeout(() => { controller.abort(); reject(new Error('timeout')); }, this.#timeoutMs); });
        const response = await Promise.race([(async () => {
          const result = await this.#fetch(`${this.#endpoint}${item.path}`, {
            method: 'POST', redirect: 'error', signal: controller.signal,
            headers: { Authorization: `Bearer ${this.#token}`, 'Content-Type': 'application/json', 'Idempotency-Key': item.key },
            body: item.body
          });
          if (!result || result.status < 200 || result.status >= 300) {
            try { if (result?.body) await result.body.cancel(); } catch { /* Ignore response contents. */ }
            return result;
          }
          const reader = result.body?.getReader();
          if (!reader) throw new Error('invalid response');
          const chunks = []; let bytes = 0;
          try {
            while (true) {
              const part = await reader.read();
              if (part.done) break;
              bytes += part.value.byteLength;
              if (bytes > 8192) { controller.abort(); throw new Error('response too large'); }
              chunks.push(Buffer.from(part.value));
            }
          } finally { reader.releaseLock(); }
          const parsed = JSON.parse(Buffer.concat(chunks).toString('utf8'));
          if (item.expected.eventId) {
            if (parsed?.event_id !== item.expected.eventId || parsed.accepted !== item.expected.count) throw new Error('invalid response');
          } else if (parsed?.test_id !== item.expected.testId || !['passed', 'failed'].includes(parsed.result)) throw new Error('invalid response');
          return result;
        })(), timeout]);
        if (response && response.status >= 200 && response.status < 300) { this.#state = 'connected'; continue; }
        this.#state = 'unresolved';
        if (!response || (response.status !== 408 && response.status !== 429 && response.status < 500)) { this.#dropped++; continue; }
      } catch { this.#state = 'unresolved'; }
      finally { clearTimeout(timer); }
      if (item.attempts >= this.#maxAttempts || Date.now() - item.created >= this.#maxAgeMs) { this.#dropped++; continue; }
      // Preserve FIFO retry order without blocking the producer or protected call.
      if (this.#queue.length === this.#maxQueue) { this.#dropped++; continue; }
      this.#queue.unshift(item);
      this.#running = false;
      this.#schedule(1000 * item.attempts);
      return;
    }
    this.#running = false;
  }
}

module.exports = { InstallationReporter };
