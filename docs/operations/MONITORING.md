# Monitoring & Alerting Guide

This guide covers monitoring, metrics, logging, and alerting for APort Agent Guardrails in production environments.

## Table of Contents

- [Overview](#overview)
- [Key Metrics](#key-metrics)
- [Logging](#logging)
- [Alerting Thresholds](#alerting-thresholds)
- [Example Dashboards](#example-dashboards)
- [Example Alert Rules](#example-alert-rules)
- [Troubleshooting](#troubleshooting)

---

## Overview

### Monitoring Architecture

```
┌─────────────────┐
│  AI Agent       │
│  (LangChain,    │
│   CrewAI, etc)  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐       ┌──────────────┐
│ APort Guardrail │──────▶│  Audit Log   │
│   Evaluator     │       │  (JSON/text) │
└────────┬────────┘       └──────────────┘
         │
         ├──────▶ Metrics (Prometheus/StatsD)
         ├──────▶ Logs (stdout/file/syslog)
         └──────▶ Traces (OpenTelemetry)
```

### Observability Pillars

1. **Metrics**: Quantitative measurements (latency, throughput, errors)
2. **Logs**: Detailed event records (decisions, denials, errors)
3. **Traces**: Distributed request tracking (coming soon)
4. **Audit Trail**: Security events for compliance

---

## Key Metrics

### Authorization Metrics

#### `aport_authorization_decisions_total`
**Type**: Counter
**Labels**: `result=[allow|deny]`, `policy_pack`, `agent_id`, `tool_name`
**Description**: Total number of authorization decisions

**Alert**: Spike in denials may indicate attack or misconfiguration

```promql
# Rate of denials
rate(aport_authorization_decisions_total{result="deny"}[5m])
```

#### `aport_authorization_duration_seconds`
**Type**: Histogram
**Labels**: `policy_pack`, `agent_id`, `mode=[local|api]`
**Description**: Authorization decision latency

**Alert**: High latency affects agent performance

```promql
# P95 latency
histogram_quantile(0.95, rate(aport_authorization_duration_seconds_bucket[5m]))
```

#### `aport_policy_evaluation_errors_total`
**Type**: Counter
**Labels**: `policy_pack`, `error_code`
**Description**: Policy evaluation errors

**Alert**: Errors may indicate policy bugs

```promql
# Error rate
rate(aport_policy_evaluation_errors_total[5m])
```

### Performance Metrics

#### `aport_passport_load_duration_seconds`
**Type**: Histogram
**Description**: Time to load and validate passport

```promql
# Slow passport loads
histogram_quantile(0.95, rate(aport_passport_load_duration_seconds_bucket[5m])) > 0.1
```

#### `aport_policy_load_duration_seconds`
**Type**: Histogram
**Labels**: `policy_pack`
**Description**: Time to load policy pack

#### `aport_subprocess_call_duration_seconds`
**Type**: Histogram
**Description**: Subprocess call duration (bash guardrail)

### API Metrics

#### `aport_api_requests_total`
**Type**: Counter
**Labels**: `endpoint`, `status_code`, `agent_id`
**Description**: Total API requests to APort API

```promql
# API error rate
rate(aport_api_requests_total{status_code=~"5.."}[5m])
```

#### `aport_api_request_duration_seconds`
**Type**: Histogram
**Labels**: `endpoint`
**Description**: API request latency

#### `aport_api_rate_limit_exceeded_total`
**Type**: Counter
**Labels**: `agent_id`
**Description**: Rate limit exceeded events

**Alert**: High rate limiting may indicate misconfiguration or attack

### Cache Metrics

#### `aport_cache_hits_total`
**Type**: Counter
**Labels**: `cache_type=[passport|policy|config]`
**Description**: Cache hits

#### `aport_cache_misses_total`
**Type**: Counter
**Labels**: `cache_type=[passport|policy|config]`
**Description**: Cache misses

**Useful**: Cache hit rate
```promql
sum(rate(aport_cache_hits_total[5m])) / (sum(rate(aport_cache_hits_total[5m])) + sum(rate(aport_cache_misses_total[5m])))
```

### Security Metrics

#### `aport_security_events_total`
**Type**: Counter
**Labels**: `event_type=[command_injection|path_traversal|validation_failure]`, `agent_id`
**Description**: Security events detected

**Alert**: Security events require immediate investigation

```promql
# Command injection attempts
rate(aport_security_events_total{event_type="command_injection"}[5m]) > 0
```

#### `aport_passport_validation_failures_total`
**Type**: Counter
**Labels**: `reason=[expired|revoked|invalid|missing_capability]`
**Description**: Passport validation failures

---

## Logging

### Log Levels

- **DEBUG**: All operations, including context data (use with caution)
- **INFO**: Authorization decisions, policy loads, cache operations
- **WARN**: Rate limits, slow operations, deprecations
- **ERROR**: Failures, exceptions, security events

### Log Format

#### Text Format (Default)
```
2026-02-19T10:30:00Z [INFO] [evaluator] Authorization decision: tool=system.command.execute agent_id=ap_abc123 decision=ALLOW policy=system.command.execute.v1 latency=47ms request_id=req_123
```

#### JSON Format (Structured)
```json
{
  "timestamp": "2026-02-19T10:30:00.123Z",
  "level": "INFO",
  "component": "evaluator",
  "event": "authorization_decision",
  "agent_id": "ap_abc123",
  "tool_name": "system.command.execute",
  "decision": "ALLOW",
  "policy_pack": "system.command.execute.v1",
  "latency_ms": 47,
  "request_id": "req_xyz789"
}
```

### Configuration

**Environment Variables**:
- `APORT_LOG_LEVEL`: DEBUG, INFO, WARN, ERROR (default: INFO)
- `APORT_LOG_FORMAT`: text, json (default: text)
- `APORT_STRUCTURED_LOGGING`: Enable JSON logging (0/1)

### Important Events to Monitor

#### Authorization Denials
```json
{
  "event": "authorization_denied",
  "policy_pack": "system.command.execute.v1",
  "reason": "Command not in allowed list",
  "command": "rm -rf /",
  "agent_id": "ap_abc123"
}
```

#### Security Events
```json
{
  "event": "security_event",
  "event_type": "command_injection_detected",
  "input": "rm; malicious",
  "agent_id": "ap_abc123",
  "blocked": true
}
```

#### Slow Operations
```json
{
  "event": "slow_operation",
  "operation": "policy_evaluation",
  "latency_ms": 523,
  "threshold_ms": 200,
  "policy_pack": "system.command.execute.v1"
}
```

---

## Alerting Thresholds

### Critical Alerts

#### High Error Rate
**Condition**: Error rate > 5% for 5 minutes
**Severity**: P1 (Critical)
**Action**: Investigate immediately

```promql
(sum(rate(aport_authorization_decisions_total{result="error"}[5m])) /
 sum(rate(aport_authorization_decisions_total[5m]))) > 0.05
```

#### Security Event Detected
**Condition**: Any command injection or path traversal attempt
**Severity**: P1 (Critical)
**Action**: Security team investigation

```promql
rate(aport_security_events_total{event_type=~"command_injection|path_traversal"}[5m]) > 0
```

#### API Down
**Condition**: API error rate > 50% for 2 minutes
**Severity**: P1 (Critical)
**Action**: Check API status, failover to local mode

```promql
(sum(rate(aport_api_requests_total{status_code=~"5.."}[2m])) /
 sum(rate(aport_api_requests_total[2m]))) > 0.5
```

### High Priority Alerts

#### High Denial Rate
**Condition**: Denial rate > 20% for 15 minutes
**Severity**: P2 (High)
**Action**: Check for policy misconfiguration or legitimate threats

```promql
(sum(rate(aport_authorization_decisions_total{result="deny"}[15m])) /
 sum(rate(aport_authorization_decisions_total[15m]))) > 0.2
```

#### High Latency
**Condition**: P95 latency > 500ms for 10 minutes
**Severity**: P2 (High)
**Action**: Check system load, optimize policies

```promql
histogram_quantile(0.95, rate(aport_authorization_duration_seconds_bucket[10m])) > 0.5
```

#### Rate Limiting Active
**Condition**: Rate limit hits > 10/minute per agent
**Severity**: P2 (High)
**Action**: Investigate agent behavior, adjust limits if legitimate

```promql
rate(aport_api_rate_limit_exceeded_total[1m]) > 10
```

### Medium Priority Alerts

#### Cache Hit Rate Low
**Condition**: Cache hit rate < 80% for 30 minutes
**Severity**: P3 (Medium)
**Action**: Review cache TTL configuration

```promql
(sum(rate(aport_cache_hits_total[30m])) /
 (sum(rate(aport_cache_hits_total[30m])) + sum(rate(aport_cache_misses_total[30m])))) < 0.8
```

#### Passport Validation Failures
**Condition**: > 5 passport failures per hour
**Severity**: P3 (Medium)
**Action**: Check for expired passports

```promql
rate(aport_passport_validation_failures_total[1h]) > 5
```

---

## Example Dashboards

### Grafana Dashboard

#### Overview Panel
- **Total Decisions** (gauge): `sum(aport_authorization_decisions_total)`
- **Allow/Deny Rate** (time series): `rate(aport_authorization_decisions_total[5m]) by (result)`
- **P95 Latency** (gauge): `histogram_quantile(0.95, rate(aport_authorization_duration_seconds_bucket[5m]))`

#### Performance Panel
- **Latency Distribution** (heatmap): `aport_authorization_duration_seconds`
- **Throughput** (time series): `sum(rate(aport_authorization_decisions_total[5m]))`
- **Cache Hit Rate** (gauge)

#### Security Panel
- **Security Events** (time series): `rate(aport_security_events_total[5m]) by (event_type)`
- **Top Denied Agents** (table): `topk(10, sum by (agent_id) (aport_authorization_decisions_total{result="deny"}))`

#### API Panel
- **API Error Rate** (time series): `rate(aport_api_requests_total{status_code=~"5.."}[5m])`
- **API Latency** (time series): `histogram_quantile(0.95, rate(aport_api_request_duration_seconds_bucket[5m]))`

### Example Grafana JSON
```json
{
  "dashboard": {
    "title": "APort Agent Guardrails",
    "panels": [
      {
        "title": "Authorization Decisions",
        "targets": [{
          "expr": "sum(rate(aport_authorization_decisions_total[5m])) by (result)"
        }]
      },
      {
        "title": "P95 Latency",
        "targets": [{
          "expr": "histogram_quantile(0.95, rate(aport_authorization_duration_seconds_bucket[5m]))"
        }]
      }
    ]
  }
}
```

---

## Example Alert Rules

### Prometheus AlertManager Rules

```yaml
groups:
  - name: aport_guardrails
    interval: 30s
    rules:
      - alert: APortHighErrorRate
        expr: |
          (sum(rate(aport_authorization_decisions_total{result="error"}[5m])) /
           sum(rate(aport_authorization_decisions_total[5m]))) > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "APort guardrail error rate is high"
          description: "Error rate is {{ $value | humanizePercentage }}. Investigate immediately."
          runbook_url: "https://github.com/aporthq/aport-agent-guardrails/blob/main/docs/operations/RUNBOOK.md#high-error-rate"

      - alert: APortSecurityEvent
        expr: rate(aport_security_events_total[5m]) > 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Security event detected: {{ $labels.event_type }}"
          description: "Agent {{ $labels.agent_id }} triggered security event: {{ $labels.event_type }}"
          runbook_url: "https://github.com/aporthq/aport-agent-guardrails/blob/main/docs/operations/RUNBOOK.md#security-event"

      - alert: APortHighLatency
        expr: histogram_quantile(0.95, rate(aport_authorization_duration_seconds_bucket[10m])) > 0.5
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "APort guardrail latency is high"
          description: "P95 latency is {{ $value | humanizeDuration }}. Check system load."

      - alert: APortAPIDown
        expr: |
          (sum(rate(aport_api_requests_total{status_code=~"5.."}[2m])) /
           sum(rate(aport_api_requests_total[2m]))) > 0.5
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "APort API is down or returning errors"
          description: "API error rate is {{ $value | humanizePercentage }}. Consider failover to local mode."
```

### PagerDuty Integration

```yaml
receivers:
  - name: 'aport-critical'
    pagerduty_configs:
      - service_key: '<YOUR_PAGERDUTY_KEY>'
        description: '{{ .GroupLabels.alertname }}: {{ .CommonAnnotations.summary }}'
```

---

## Troubleshooting

### High Latency

**Symptoms**: P95 latency > 200ms

**Possible Causes**:
1. Slow disk I/O (passport/policy loading)
2. Complex policy evaluation
3. Slow API calls
4. Insufficient caching

**Investigation**:
```bash
# Check slow operations in logs
grep "slow_operation" /var/log/aport/audit.log

# Check file system performance
iostat -x 1

# Check API latency
curl -w "@curl-format.txt" -o /dev/null -s https://api.aport.io/health
```

**Resolution**:
- Enable caching: `APORT_ENABLE_CACHING=1`
- Increase cache TTL: `APORT_PASSPORT_CACHE_TTL=120`
- Use local mode instead of API mode
- Optimize policy complexity

### High Denial Rate

**Symptoms**: Denial rate > 20%

**Possible Causes**:
1. Policy too restrictive
2. Attack in progress
3. Agent misconfiguration

**Investigation**:
```bash
# Check denial reasons
jq '.reasons[] | select(.code | startswith("oap.policy")) | .message' /var/log/aport/audit.log | sort | uniq -c

# Check top denied agents
jq 'select(.decision == "DENY") | .agent_id' /var/log/aport/audit.log | sort | uniq -c | sort -rn | head -10
```

**Resolution**:
- Review policy rules
- Check if denials are legitimate (security events)
- Update agent configuration
- Add missing capabilities to passports

### Security Events

**Symptoms**: `security_event` logs appearing

**Immediate Actions**:
1. Block agent if attack confirmed
2. Review recent agent activity
3. Check for compromised credentials
4. Review security policies

**Investigation**:
```bash
# List all security events
grep "security_event" /var/log/aport/audit.log | jq .

# Check specific agent's history
grep "agent_id.*ap_abc123" /var/log/aport/audit.log | jq .
```

---

## Integration Examples

### Datadog

```python
from datadog import initialize, statsd

initialize(statsd_host='localhost', statsd_port=8125)

# Increment decision counter
statsd.increment('aport.authorization.decisions', tags=[f'result:{decision}', f'agent_id:{agent_id}'])

# Record latency
statsd.histogram('aport.authorization.duration', duration_ms, tags=[f'policy_pack:{policy_pack}'])
```

### Splunk

```bash
# Forward APort logs to Splunk
tail -f /var/log/aport/audit.log | /opt/splunkforwarder/bin/splunk add oneshot -
```

Splunk Query:
```spl
index=aport event="authorization_decision"
| stats count by result, policy_pack
| where count > 100
```

### ELK Stack

Filebeat configuration:
```yaml
filebeat.inputs:
  - type: log
    paths:
      - /var/log/aport/audit.log
    json.keys_under_root: true
    json.add_error_key: true

output.elasticsearch:
  hosts: ["localhost:9200"]
  index: "aport-%{+yyyy.MM.dd}"
```

Kibana Query:
```
event:"authorization_denied" AND agent_id:"ap_*"
```

---

## Best Practices

1. **Always Enable Structured Logging** in production (`APORT_LOG_FORMAT=json`)
2. **Set Appropriate Log Levels**: INFO for production, DEBUG only when troubleshooting
3. **Monitor Security Events**: Alert on any command injection or path traversal attempts
4. **Track Latency**: Alert on P95 > 200ms
5. **Review Audit Logs Weekly**: Look for patterns in denials
6. **Set Up Alerting**: Critical alerts to PagerDuty, warnings to Slack
7. **Regular Dashboard Reviews**: Weekly team reviews of key metrics

---

## See Also

- [Configuration Guide](../user/CONFIGURATION.md)
- [Security Policy](../../SECURITY.md)
- [Troubleshooting Guide](../user/TROUBLESHOOTING.md)
- [Error Codes](../development/ERROR_CODES.md)
