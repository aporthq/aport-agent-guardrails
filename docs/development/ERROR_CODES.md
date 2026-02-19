# APort Error Codes Reference

This document defines all error codes used in APort Agent Guardrails. Error codes follow the format: `oap.<category>.<specific>`

## Error Code Format

```
oap.<category>.<specific>
```

- **oap**: Prefix for all Open Agent Passport errors
- **category**: Broad category (invalid_input, policy, passport, api, etc.)
- **specific**: Specific error type

## Error Response Format

### JSON Format (Python/API)

```json
{
  "allow": false,
  "reasons": [{
    "code": "oap.invalid_input.tool_name",
    "message": "Tool name contains invalid characters",
    "details": {
      "tool_name": "rm; malicious",
      "allowed_pattern": "^[a-zA-Z0-9._-]+$"
    }
  }],
  "request_id": "req_1234567890",
  "timestamp": "2026-02-19T10:30:00Z"
}
```

### Text Format (Bash)

```
ERROR: oap.invalid_input.tool_name
Tool name contains invalid characters
Details: tool_name='rm; malicious', allowed_pattern='^[a-zA-Z0-9._-]+$'
Request ID: req_1234567890
```

---

## Error Categories

### 1. Invalid Input Errors (`oap.invalid_input.*`)

#### `oap.invalid_input.tool_name`
**Description**: Tool name contains invalid characters or exceeds length limit

**Cause**: Tool name doesn't match pattern `^[a-zA-Z0-9._-]+$` or exceeds 128 characters

**Resolution**:
- Use only alphanumeric characters, dots, underscores, and hyphens in tool names
- Keep tool names under 128 characters

**Example**:
```json
{
  "code": "oap.invalid_input.tool_name",
  "message": "Tool name contains invalid characters",
  "details": {
    "tool_name": "rm; malicious",
    "allowed_pattern": "^[a-zA-Z0-9._-]+$",
    "max_length": 128
  }
}
```

#### `oap.invalid_input.context_too_large`
**Description**: Context JSON exceeds maximum size limit

**Cause**: Context data is larger than 100KB

**Resolution**:
- Reduce context data size
- Remove unnecessary fields
- Consider summarizing large data

**Configuration**: Set `APORT_MAX_CONTEXT_SIZE` to increase limit (not recommended)

#### `oap.invalid_input.context_too_nested`
**Description**: Context JSON nesting depth exceeds limit

**Cause**: Context has more than 10 levels of nesting

**Resolution**:
- Flatten nested structures
- Use simpler data representation

#### `oap.invalid_input.context_not_serializable`
**Description**: Context cannot be serialized to JSON

**Cause**: Context contains non-JSON-serializable objects

**Resolution**:
- Ensure all context values are JSON-serializable types
- Convert objects to dictionaries before passing as context

#### `oap.invalid_input.agent_id`
**Description**: Agent ID has invalid format

**Cause**: Agent ID doesn't match expected format `^ap_[a-zA-Z0-9_]+$`

**Resolution**:
- Use agent IDs from APort API
- Format: `ap_` prefix followed by alphanumeric characters

#### `oap.invalid_input.policy_pack_id`
**Description**: Policy pack ID contains invalid characters

**Cause**: Policy pack ID doesn't match pattern `^[a-zA-Z0-9._-]+$`

**Resolution**:
- Use valid policy pack IDs from APort policies
- Follow naming convention: `category.subcategory.action.v#`

---

### 2. Path Security Errors (`oap.path.*`)

#### `oap.path.not_allowed`
**Description**: File path is outside allowed directories

**Cause**: Path is not within `~/.openclaw/`, `~/.aport/`, or `/tmp/aport-*`

**Resolution**:
- Use standard APort directories for passports and config
- Contact administrator to add custom allowed directories

**Security Note**: This is a security feature to prevent path traversal attacks

#### `oap.path.traversal_attempt`
**Description**: Path contains traversal sequences

**Cause**: Path contains `../` or `/..` sequences

**Resolution**:
- Use absolute paths
- Remove parent directory references

**Security Note**: Path traversal attempts are blocked for security

#### `oap.path.invalid_characters`
**Description**: Path contains invalid characters

**Cause**: Path contains null bytes or other dangerous characters

**Resolution**:
- Use standard filesystem-safe characters
- Remove special characters from paths

#### `oap.path.resolution_error`
**Description**: Failed to resolve path to absolute location

**Cause**: Path doesn't exist or filesystem error

**Resolution**:
- Verify path exists
- Check filesystem permissions
- Verify filesystem is mounted

---

### 3. Passport Errors (`oap.passport.*`)

#### `oap.passport.not_found`
**Description**: Passport file not found

**Cause**: No passport file at expected location

**Resolution**:
```bash
# Create a passport
npx @aporthq/agent-guardrails openclaw
# Or
aport-create-passport.sh
```

**See**: [Passport Setup Guide](https://github.com/aporthq/agent-guardrails#passport-setup)

#### `oap.passport.invalid_format`
**Description**: Passport file is not valid JSON or missing required fields

**Cause**: Passport file is corrupted or manually edited incorrectly

**Resolution**:
- Regenerate passport using official tools
- Do not manually edit passport files
- Verify JSON syntax is valid

**Required Fields**: `passport_id`, `agent_id`, `owner`, `status`, `spec_version`, `capabilities`

#### `oap.passport.expired`
**Description**: Passport has expired

**Cause**: `expires_at` timestamp is in the past

**Resolution**:
- Generate new passport
- Contact APort administrator for renewal

#### `oap.passport.revoked`
**Description**: Passport has been revoked

**Cause**: `status` field is `"revoked"`

**Resolution**:
- Contact APort administrator
- Generate new passport if authorized

#### `oap.passport.missing_capability`
**Description**: Passport doesn't have required capability for operation

**Cause**: Capability not listed in passport's `capabilities` array

**Resolution**:
- Request capability be added to passport
- Generate new passport with required capabilities
- Use different operation that doesn't require this capability

**Example**:
```json
{
  "code": "oap.passport.missing_capability",
  "message": "Passport lacks required capability: git.repository.merge",
  "details": {
    "required_capability": "git.repository.merge",
    "passport_capabilities": ["system.command.execute", "messaging.message.send"]
  }
}
```

---

### 4. Policy Errors (`oap.policy.*`)

#### `oap.policy.not_found`
**Description**: Policy pack not found

**Cause**: Policy pack doesn't exist in policies directory

**Resolution**:
- Verify policy pack ID is correct
- Update policy submodule: `git submodule update --init --recursive`
- Check policy pack version exists

#### `oap.policy.invalid_format`
**Description**: Policy pack file is invalid

**Cause**: Policy JSON is malformed or missing required fields

**Resolution**:
- Update policy submodule to latest version
- Report issue if policy pack is from official repository

#### `oap.policy.evaluation_failed`
**Description**: Policy evaluation encountered an error

**Cause**: Logic error in policy rules or invalid data

**Resolution**:
- Check audit log for details
- Verify context data is complete
- Report issue if policy is from official repository

#### `oap.policy.evaluation_timeout`
**Description**: Policy evaluation exceeded timeout

**Cause**: Complex policy or infinite loop in evaluation

**Resolution**:
- Simplify policy rules
- Increase timeout: `APORT_SUBPROCESS_TIMEOUT=60`
- Report performance issue to policy maintainer

**Configuration**: Default timeout is 30 seconds

#### `oap.policy.denied`
**Description**: Operation denied by policy

**Cause**: Operation violates policy rules

**Resolution**: This is expected behavior. The operation is not allowed by your current policy configuration.

**Common Reasons**:
- Command not in allowed list
- Limit exceeded (e.g., max files in PR)
- Pattern matched blocked list
- Missing approval requirement

---

### 5. API Errors (`oap.api.*`)

#### `oap.api.connection_failed`
**Description**: Failed to connect to APort API

**Cause**: Network error, API down, or wrong URL

**Resolution**:
- Check internet connectivity
- Verify API URL: `echo $APORT_API_URL`
- Check API status: https://status.aport.io
- Verify firewall allows outbound HTTPS

**Configuration**: `APORT_API_URL` (default: https://api.aport.io)

#### `oap.api.authentication_failed`
**Description**: API authentication failed

**Cause**: Invalid or missing API key

**Resolution**:
- Verify API key is set: `echo $APORT_API_KEY | head -c 8`
- Generate new API key from APort dashboard
- Check key format: should start with `aprt_`

**Configuration**: `APORT_API_KEY`

#### `oap.api.rate_limit_exceeded`
**Description**: API rate limit exceeded

**Cause**: Too many requests in time window

**Resolution**:
- Wait for rate limit to reset (see `retry-after` header)
- Reduce request frequency
- Contact APort for higher rate limits
- Use local evaluation mode instead of API mode

**Configuration**: Default: 60 requests/minute per agent

#### `oap.api.timeout`
**Description**: API request timed out

**Cause**: Slow network or API overload

**Resolution**:
- Retry request
- Increase timeout: `APORT_API_TIMEOUT=30`
- Check network latency to API

#### `oap.api.invalid_response`
**Description**: API returned invalid response format

**Cause**: API error or version mismatch

**Resolution**:
- Check API status
- Update client library to latest version
- Report issue with request ID

#### `oap.api.not_found_404`
**Description**: Resource not found (404)

**Cause**: Agent ID, policy pack, or passport not found in API

**Resolution**:
- Verify agent ID is correct
- Check resource exists in APort dashboard
- Verify API URL is correct

---

### 6. Configuration Errors (`oap.config.*`)

#### `oap.config.not_found`
**Description**: Configuration file not found

**Cause**: No config file at expected locations

**Resolution**:
- Run setup: `npx @aporthq/agent-guardrails <framework>`
- Create config manually in `~/.aport/<framework>/config.yaml`

**Expected Locations**:
- `~/.aport/<framework>/config.yaml`
- `~/.openclaw/config.yaml`
- `./.aport/config.yaml`

#### `oap.config.invalid_format`
**Description**: Configuration file is invalid YAML/JSON

**Cause**: Syntax error in config file

**Resolution**:
- Validate YAML syntax
- Regenerate config with setup tool
- Check for tabs vs. spaces in YAML

#### `oap.config.missing_required`
**Description**: Required configuration option is missing

**Cause**: Config file missing required field

**Resolution**:
- Add missing field
- Run setup tool to generate complete config

---

### 7. System Errors (`oap.system.*`)

#### `oap.system.evaluator_error`
**Description**: Guardrail script execution failed

**Cause**: Script error or missing dependency

**Resolution**:
- Check script exists: `which aport-guardrail.sh`
- Verify dependencies: `jq`, `bash`, `grep`
- Check script permissions: `chmod +x`
- Review error logs

#### `oap.system.command_injection_detected`
**Description**: Potential command injection attempt blocked

**Cause**: Input contains bash metacharacters

**Resolution**: This is a security feature. Do not attempt to bypass.

**Security Note**: Commands with these characters are blocked: `$`, `` ` ``, `|`, `&`, `;`, `<`, `>`, `()`, `{}`, `[]`, `*`, `?`, `\`

#### `oap.system.dependency_missing`
**Description**: Required system dependency not found

**Cause**: Missing `jq`, `curl`, or other required tool

**Resolution**:
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq

# RHEL/CentOS
sudo yum install jq
```

#### `oap.system.insufficient_permissions`
**Description**: Insufficient file system permissions

**Cause**: Cannot read passport/config or write decision/logs

**Resolution**:
- Check file permissions
- Verify user has read access to config directories
- Verify user has write access to data directories

---

### 8. Rate Limiting Errors (`oap.rate_limit.*`)

#### `oap.rate_limit.exceeded`
**Description**: Request rate limit exceeded

**Cause**: Too many requests in time window

**Resolution**:
- Wait for rate limit reset
- Check `retry-after` seconds in response
- Reduce request frequency

**Configuration**:
- `APORT_RATE_LIMIT_REQUESTS_PER_MINUTE` (default: 60)
- `APORT_RATE_LIMIT_BURST` (default: 10)

#### `oap.rate_limit.per_agent`
**Description**: Per-agent rate limit exceeded

**Cause**: Specific agent exceeded its rate limit

**Resolution**:
- Isolates rate limiting per agent
- One agent's high usage doesn't affect others
- Wait for reset or optimize agent behavior

---

### 9. Validation Errors (`oap.validation.*`)

#### `oap.validation.failed`
**Description**: Generic validation failure

**Cause**: Input failed validation checks

**Resolution**: See details field for specific validation failure

#### `oap.validation.required_field`
**Description**: Required field is missing

**Cause**: Missing required field in request

**Resolution**: Add required field to request

#### `oap.validation.invalid_format`
**Description**: Field has invalid format

**Cause**: Field doesn't match expected format

**Resolution**: Check field format in API documentation

---

### 10. Misconfigured Errors (`oap.misconfigured.*`)

#### `oap.misconfigured`
**Description**: System is misconfigured and cannot operate

**Cause**: Missing passport or guardrail script in local mode

**Resolution**:
```bash
# Check passport exists
ls -la ~/.openclaw/passport.json

# Check guardrail script exists
ls -la ~/.openclaw/.skills/aport-guardrail.sh

# Run setup if missing
npx @aporthq/agent-guardrails openclaw
```

**Legacy Mode**: Set `APORT_FAIL_OPEN_WHEN_MISSING_CONFIG=1` to allow by default (not recommended)

---

## Error Handling Best Practices

### For Users

1. **Read the error message carefully** - Error messages include resolution steps
2. **Check the error code** - Use this document to understand the issue
3. **Look at error details** - Additional context is in the `details` field
4. **Check configuration** - Many errors are due to misconfiguration
5. **Review logs** - Audit logs contain additional context

### For Developers

1. **Always include error codes** - Use constants from this document
2. **Provide actionable messages** - Tell users how to fix the issue
3. **Include context in details** - Add relevant data to help debugging
4. **Log security events** - All security-related errors should be audited
5. **Use structured format** - Follow JSON/text format standards

### Example: Good Error Handling

```python
from aport_guardrails.core.validation import validate_tool_name
from aport_guardrails.core.errors import ErrorCode, create_error_response

def evaluate_tool(tool_name: str, context: dict):
    # Validate input
    validation_result = validate_tool_name(tool_name)
    if not validation_result.valid:
        return create_error_response(
            code=ErrorCode.INVALID_TOOL_NAME,
            message=validation_result.error_message,
            details=validation_result.details,
            resolution="Use only alphanumeric characters, dots, underscores, and hyphens"
        )

    # Continue with evaluation...
```

---

## Troubleshooting by Error Category

### Security Errors
- **DO NOT** try to bypass security features
- **DO** report potential false positives
- **DO** review security documentation

### Configuration Errors
- **Start with**: Run setup wizard
- **Check**: Environment variables
- **Verify**: File locations and permissions

### API Errors
- **Check**: Network connectivity
- **Verify**: API keys and credentials
- **Review**: API status page

### Policy Errors
- **Understand**: Policy rules and limits
- **Request**: Policy modifications from administrator
- **Alternative**: Use different operation

---

## Request IDs

All errors include a unique request ID for tracking and debugging:

**Format**: `req_<timestamp>_<random>`

**Example**: `req_1771528805673_2y4gr0`

**Usage**:
- Include in bug reports
- Reference in support requests
- Correlate with audit logs

---

## See Also

- [Security Policy](../../SECURITY.md)
- [Configuration Guide](../user/CONFIGURATION.md)
- [Troubleshooting Guide](../user/TROUBLESHOOTING.md)
- [API Reference](../api/README.md)
