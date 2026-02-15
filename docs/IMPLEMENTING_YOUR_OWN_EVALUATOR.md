# Implementing Your Own Local Evaluator

If you want to implement your own local policy evaluator instead of using the APort cloud API, you have everything you need in this repository!

## What You Have

### 1. Open Agent Passport (OAP) Specification

The complete OAP v1.0 specification is available at:
- **GitHub:** https://github.com/aporthq/aport-spec
- **Local:** `external/aport-spec/` (git submodule)

**Key documents:**
- `oap/oap-spec.md` - Complete specification
- `oap/passport-schema.json` - JSON schema for passports
- `oap/decision-schema.json` - JSON schema for decisions
- `oap/policy-schema.json` - JSON schema for policy packs

### 2. Policy Pack Definitions

All policy pack JSON files are available at:
- **GitHub:** https://github.com/aporthq/aport-policies
- **Local:** `external/aport-policies/` (git submodule)

Each policy pack includes:
- `policy.json` - Complete policy definition with evaluation rules
- `examples/` - Example contexts showing expected input format
- `tests/` - Test cases showing allow/deny scenarios

**Example policy pack structure:**
```
external/aport-policies/
  system.command.execute.v1/
    policy.json           # Policy definition
    examples/
      allow-command.json  # Example allowed context
      deny-command.json   # Example denied context
    tests/
      system-command.test.js  # Test suite
```

### 3. Evaluation Rules Format

Each policy pack contains `evaluation_rules` that define the policy logic:

```json
{
  "id": "system.command.execute.v1",
  "evaluation_rules_version": "1.0",
  "evaluation_rules": [
    {
      "name": "passport_status_active",
      "type": "expression",
      "condition": "passport.status == 'active'",
      "deny_code": "oap.passport_suspended",
      "description": "Passport must be active"
    },
    {
      "name": "command_allowed",
      "type": "expression",
      "condition": "context.command IN limits.allowed_commands",
      "deny_code": "oap.command_not_allowed",
      "description": "Command must be in allowed list"
    },
    {
      "name": "blocked_pattern_check",
      "type": "custom_validator",
      "validator": "validateBlockedPatterns",
      "deny_code": "oap.blocked_pattern",
      "description": "Command must not contain blocked patterns"
    }
  ]
}
```

### 4. Required Context Schema

Each policy pack defines the expected context format in `required_context`:

```json
{
  "required_context": {
    "command": {
      "type": "string",
      "description": "The command to execute",
      "required": true
    },
    "args": {
      "type": "array",
      "description": "Command arguments",
      "required": false
    },
    "cwd": {
      "type": "string",
      "description": "Working directory",
      "required": false
    }
  }
}
```

## Implementation Guide

### Option 1: Expression-Based Evaluator (Simple)

If you only need to support `type: "expression"` rules, you can implement a simple expression evaluator.

**Supported operators:**
- Comparison: `==`, `!=`, `>`, `<`, `>=`, `<=`
- Logical: `AND`, `OR`, `NOT`
- Membership: `IN`, `NOT IN`
- String: `CONTAINS`, `STARTS_WITH`, `ENDS_WITH`

**Example implementation (pseudocode):**

```python
def evaluate_expression(rule, passport, context, limits):
    """
    Evaluate an expression rule against passport + context

    Returns: (allowed: bool, deny_code: str, message: str)
    """
    condition = rule["condition"]

    # Replace variables with values
    condition = condition.replace("passport.status", f'"{passport["status"]}"')
    condition = condition.replace("context.command", f'"{context["command"]}"')
    condition = condition.replace("limits.allowed_commands", str(limits["allowed_commands"]))

    # Handle IN operator
    if " IN " in condition:
        # e.g., "ls" IN ["ls", "pwd", "git"]
        value, list_str = condition.split(" IN ")
        value = value.strip().strip('"')
        list_items = eval(list_str)  # Parse list (use proper parser in production!)
        result = value in list_items
    else:
        # Simple comparison
        result = eval(condition)  # Use proper expression parser in production!

    if result:
        return (True, None, None)
    else:
        return (False, rule["deny_code"], rule["description"])
```

**⚠️ Security Warning:** Don't use `eval()` in production! Use a proper expression parser that restricts operations.

### Option 2: Full Evaluator (Advanced)

For a complete implementation with custom validators, you'll need:

1. **Expression evaluator** - Handle all expression types safely
2. **Custom validator registry** - Map validator names to functions
3. **Standard checks** - Passport status, capabilities, assurance levels
4. **Decision builder** - Create OAP v1.0 compliant decision objects

**Example implementation structure:**

```python
class PolicyEvaluator:
    def __init__(self):
        self.custom_validators = {
            "validateBlockedPatterns": self.validate_blocked_patterns,
            "validateRateLimit": self.validate_rate_limit,
            # ... more validators
        }

    def evaluate_policy(self, policy_pack, passport, context):
        """
        Evaluate a policy pack against passport + context

        Returns: Decision (OAP v1.0 compliant)
        """
        # 1. Standard checks
        if passport["status"] != "active":
            return self.deny("oap.passport_suspended", "Passport is suspended")

        # 2. Capability check
        required_caps = policy_pack.get("requires_capabilities", [])
        passport_caps = [c["id"] for c in passport.get("capabilities", [])]
        for cap in required_caps:
            if cap not in passport_caps:
                return self.deny("oap.unknown_capability", f"Missing capability: {cap}")

        # 3. Assurance level check
        min_assurance = policy_pack.get("min_assurance", "L0")
        if not self.check_assurance(passport["assurance_level"], min_assurance):
            return self.deny("oap.assurance_insufficient", "Insufficient assurance level")

        # 4. Evaluation rules
        limits = passport.get("limits", {})
        for rule in policy_pack.get("evaluation_rules", []):
            if rule["type"] == "expression":
                result = self.evaluate_expression(rule, passport, context, limits)
            elif rule["type"] == "custom_validator":
                validator_fn = self.custom_validators[rule["validator"]]
                result = validator_fn(passport, context, limits)
            else:
                result = (False, "oap.policy_error", f"Unknown rule type: {rule['type']}")

            if not result[0]:  # If denied
                return self.deny(result[1], result[2])

        # 5. All checks passed
        return self.allow()

    def deny(self, code, message):
        return {
            "decision_id": f"local-{uuid.uuid4()}",
            "policy_id": "system.command.execute.v1",
            "passport_id": passport["passport_id"],
            "owner_id": passport["owner_id"],
            "assurance_level": passport["assurance_level"],
            "allow": False,
            "reasons": [{"code": code, "message": message}],
            "issued_at": datetime.utcnow().isoformat() + "Z",
            "expires_at": (datetime.utcnow() + timedelta(hours=1)).isoformat() + "Z",
            "passport_digest": self.compute_digest(passport),
            "signature": "ed25519:local-unsigned",
            "kid": "oap:local:dev-key"
        }

    def allow(self):
        # Similar to deny() but with allow=True
        pass
```

### Option 3: Fork the APort Evaluator (Easiest)

The APort cloud API uses a generic evaluator that's designed to work with any policy pack. If you want the exact same implementation, you can:

1. **Contact us** - We may open-source the core evaluator in the future
2. **Request access** - We can provide the evaluator source code for enterprise customers
3. **Use the API** - The easiest option (see `src/evaluator.js` in this repo)

## Testing Your Implementation

### Test Data

Use the test cases from the policy pack directories:

```bash
# Get test passport
cat external/aport-policies/system.command.execute.v1/tests/fixtures/passport.json

# Get test contexts (allow case)
cat external/aport-policies/system.command.execute.v1/examples/allow-command.json

# Get test contexts (deny case)
cat external/aport-policies/system.command.execute.v1/examples/deny-command.json
```

### Test Cases

Each policy pack includes a test suite showing expected behavior:

```javascript
// Example from system.command.execute.v1/tests/system-command.test.js
describe("system.command.execute.v1", () => {
  it("should allow commands in allowed list", async () => {
    const decision = await evaluatePolicy(policyPack, passport, {
      command: "ls",
      args: ["-la"]
    });

    expect(decision.allow).toBe(true);
  });

  it("should deny commands not in allowed list", async () => {
    const decision = await evaluatePolicy(policyPack, passport, {
      command: "rm",
      args: ["-rf", "/"]
    });

    expect(decision.allow).toBe(false);
    expect(decision.reasons[0].code).toBe("oap.command_not_allowed");
  });

  it("should deny blocked patterns", async () => {
    const decision = await evaluatePolicy(policyPack, passport, {
      command: "ls ; rm -rf /"  // Command injection
    });

    expect(decision.allow).toBe(false);
    expect(decision.reasons[0].code).toBe("oap.blocked_pattern");
  });
});
```

### Compliance Validation

Your implementation should pass the OAP v1.0 compliance tests:

1. **Passport validation** - Check status, spec_version, required fields
2. **Capability validation** - Check passport has required capabilities
3. **Assurance validation** - Check passport meets minimum assurance level
4. **Context validation** - Check context has required fields
5. **Decision format** - Check decision matches OAP v1.0 schema
6. **Signature** - Check decision is properly signed (or marked unsigned)

## Example Implementations

### Bash (Simple)

See `bin/aport-guardrail.sh` in this repo for a basic bash implementation. **Note:** This only handles simple checks and is not production-ready.

### Node.js (API Client)

See `src/evaluator.js` in this repo for a Node.js client that calls the APort cloud API.

### Python (Full Implementation)

Coming soon! We're working on a reference implementation in Python.

### Go (Full Implementation)

Coming soon! We're working on a reference implementation in Go.

## Security Considerations

### Expression Evaluation

⚠️ **Never use `eval()` or `exec()` directly** - This allows arbitrary code execution

✅ **Use a restricted expression parser** - Only allow specific operators and functions

Example of a safe expression parser (Python):
```python
import ast
import operator

# Whitelist of allowed operations
ALLOWED_OPS = {
    ast.Eq: operator.eq,
    ast.NotEq: operator.ne,
    ast.Lt: operator.lt,
    ast.LtE: operator.le,
    ast.Gt: operator.gt,
    ast.GtE: operator.ge,
    ast.And: operator.and_,
    ast.Or: operator.or_,
    ast.Not: operator.not_,
    ast.In: lambda x, y: x in y,
    ast.NotIn: lambda x, y: x not in y,
}

def safe_eval(expr, context):
    """
    Safely evaluate an expression with restricted operations
    """
    tree = ast.parse(expr, mode='eval')

    def eval_node(node):
        if isinstance(node, ast.Expression):
            return eval_node(node.body)
        elif isinstance(node, ast.Compare):
            left = eval_node(node.left)
            result = left
            for op, comparator in zip(node.ops, node.comparators):
                if type(op) not in ALLOWED_OPS:
                    raise ValueError(f"Operation {type(op).__name__} not allowed")
                right = eval_node(comparator)
                result = ALLOWED_OPS[type(op)](result, right)
            return result
        elif isinstance(node, ast.Name):
            # Look up variable in context
            return context.get(node.id)
        elif isinstance(node, ast.Constant):
            return node.value
        else:
            raise ValueError(f"Node type {type(node).__name__} not allowed")

    return eval_node(tree)
```

### Custom Validators

Custom validators should:
- ✅ Be pure functions (no side effects)
- ✅ Have timeouts (don't block forever)
- ✅ Validate all inputs (don't trust context data)
- ✅ Return consistent formats (allow/deny, code, message)
- ⚠️ Be careful with DB lookups (rate limits, caching)

### Decision Signing

For production use, decisions should be Ed25519 signed:

```python
import nacl.signing
import nacl.encoding
import json

# Generate signing key (do this once, store securely)
signing_key = nacl.signing.SigningKey.generate()
verify_key = signing_key.verify_key

# Sign decision
def sign_decision(decision, signing_key):
    # Create canonical JSON (sorted keys)
    canonical = json.dumps(decision, sort_keys=True, separators=(',', ':'))

    # Sign with Ed25519
    signature = signing_key.sign(canonical.encode('utf-8'))

    # Add signature to decision
    decision["signature"] = f"ed25519:{signature.signature.hex()}"
    decision["kid"] = "oap:local:your-key-id"

    return decision
```

## Contributing

If you implement your own evaluator, we'd love to hear about it!

- Share your implementation: https://github.com/aporthq/aport-agent-guardrails/discussions
- Submit a PR: https://github.com/aporthq/aport-agent-guardrails/pulls
- Join Discord: https://discord.gg/aport

## Resources

- **OAP Spec:** https://github.com/aporthq/aport-spec
- **Policy Packs:** https://github.com/aporthq/aport-policies
- **API Reference:** https://api.aport.io/docs
- **Discord:** https://discord.gg/aport

## License

All OAP specifications and policy pack definitions are Apache 2.0 licensed. You're free to implement your own evaluator using these specifications.

The APort cloud API is proprietary software. The reference evaluator implementation (if/when open sourced) will be Apache 2.0 licensed.
