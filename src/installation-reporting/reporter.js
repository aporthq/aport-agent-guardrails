'use strict';

const { randomUUID } = require('node:crypto');
const { deliver } = require('./transport');
const { validateHandoff, serializeReport, serializeTestResult } = require('./contract');

// Compatibility in-memory API; adapters use the durable spool instead.
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
      const result = await deliver({ installation_id: this.#installationId, reporter_token: this.#token },
        this.#endpoint.split('/api/agent-installations/')[0], JSON.parse(item.body), item.expected.testId,
        item.key, { fetch: this.#fetch, timeoutMs: this.#timeoutMs });
      if (result.accepted) { this.#state = this.#dropped ? 'unresolved' : 'connected'; continue; }
      this.#state = 'unresolved';
      if (!result.retry) { this.#dropped++; continue; }
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
