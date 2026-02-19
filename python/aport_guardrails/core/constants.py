"""
Constants and configuration defaults for APort Guardrails.
All magic numbers and hardcoded values should be defined here.
"""

import os

# ============================================================================
# TIMEOUTS (seconds)
# ============================================================================

# Default timeout for subprocess guardrail script execution
DEFAULT_SUBPROCESS_TIMEOUT = int(os.environ.get("APORT_SUBPROCESS_TIMEOUT", "30"))

# Default timeout for API requests
DEFAULT_API_TIMEOUT = int(os.environ.get("APORT_API_TIMEOUT", "15"))

# Timeout for loading policy packs
DEFAULT_POLICY_LOAD_TIMEOUT = int(os.environ.get("APORT_POLICY_LOAD_TIMEOUT", "5"))

# ============================================================================
# SIZE LIMITS (bytes)
# ============================================================================

# Maximum tool name length (characters)
MAX_TOOL_NAME_LENGTH = int(os.environ.get("APORT_MAX_TOOL_NAME_LENGTH", "128"))

# Maximum agent ID length (characters)
MAX_AGENT_ID_LENGTH = int(os.environ.get("APORT_MAX_AGENT_ID_LENGTH", "128"))

# Maximum policy pack ID length (characters)
MAX_POLICY_PACK_ID_LENGTH = int(os.environ.get("APORT_MAX_POLICY_PACK_ID_LENGTH", "128"))

# Maximum context JSON size (bytes) - default 100KB
MAX_CONTEXT_SIZE_BYTES = int(os.environ.get("APORT_MAX_CONTEXT_SIZE", str(100 * 1024)))

# Maximum passport file size (bytes) - default 1MB
MAX_PASSPORT_SIZE_BYTES = int(os.environ.get("APORT_MAX_PASSPORT_SIZE", str(1024 * 1024)))

# Maximum policy pack file size (bytes) - default 10MB
MAX_POLICY_PACK_SIZE_BYTES = int(os.environ.get("APORT_MAX_POLICY_PACK_SIZE", str(10 * 1024 * 1024)))

# Maximum nesting depth for context JSON
MAX_CONTEXT_NESTING_DEPTH = int(os.environ.get("APORT_MAX_CONTEXT_NESTING", "10"))

# Maximum log message length (characters)
MAX_LOG_MESSAGE_LENGTH = int(os.environ.get("APORT_MAX_LOG_MESSAGE_LENGTH", "200"))

# ============================================================================
# RATE LIMITING
# ============================================================================

# Default requests per minute
DEFAULT_RATE_LIMIT_RPM = int(os.environ.get("APORT_RATE_LIMIT_REQUESTS_PER_MINUTE", "60"))

# Default burst allowance
DEFAULT_RATE_LIMIT_BURST = int(os.environ.get("APORT_RATE_LIMIT_BURST", "10"))

# Rate limit per agent (if True, each agent gets its own limit)
RATE_LIMIT_PER_AGENT = os.environ.get("APORT_RATE_LIMIT_PER_AGENT", "true").lower() in ("1", "true", "yes")

# ============================================================================
# RETRY LOGIC
# ============================================================================

# Maximum API retry attempts
MAX_API_RETRIES = int(os.environ.get("APORT_MAX_API_RETRIES", "3"))

# API retry backoff (milliseconds)
API_RETRY_BACKOFF_MS = int(os.environ.get("APORT_API_RETRY_BACKOFF_MS", "1000"))

# Exponential backoff multiplier
API_RETRY_BACKOFF_MULTIPLIER = float(os.environ.get("APORT_API_RETRY_BACKOFF_MULTIPLIER", "2.0"))

# ============================================================================
# CACHING
# ============================================================================

# Passport file cache TTL (seconds)
PASSPORT_CACHE_TTL_SECONDS = int(os.environ.get("APORT_PASSPORT_CACHE_TTL", "60"))

# Policy pack cache TTL (seconds)
POLICY_CACHE_TTL_SECONDS = int(os.environ.get("APORT_POLICY_CACHE_TTL", "60"))

# Config file cache TTL (seconds)
CONFIG_CACHE_TTL_SECONDS = int(os.environ.get("APORT_CONFIG_CACHE_TTL", "300"))

# Enable caching (default: True)
ENABLE_FILE_CACHING = os.environ.get("APORT_ENABLE_CACHING", "true").lower() in ("1", "true", "yes")

# ============================================================================
# API CONFIGURATION
# ============================================================================

# Default API URL
DEFAULT_API_URL = os.environ.get("APORT_API_URL", "https://api.aport.io")

# API key from environment
API_KEY = os.environ.get("APORT_API_KEY")

# SSL verification (default: True, can be disabled with APORT_VERIFY_SSL=0)
VERIFY_SSL = os.environ.get("APORT_VERIFY_SSL", "1") != "0"

# ============================================================================
# PATHS
# ============================================================================

# Default passport paths by framework
DEFAULT_PASSPORT_PATHS = {
    "openclaw": "~/.openclaw/passport.json",
    "langchain": "~/.aport/langchain/passport.json",
    "crewai": "~/.aport/crewai/passport.json",
    "cursor": "~/.aport/cursor/passport.json",
    "n8n": "~/.aport/n8n/passport.json",
}

# Allowed base directories for passport files (security)
ALLOWED_PASSPORT_BASE_DIRS = [
    "~/.openclaw",
    "~/.aport",
    "/tmp/aport-",  # Special handling: must start with aport-
]

# Default guardrail script path
DEFAULT_GUARDRAIL_SCRIPT = os.environ.get(
    "APORT_GUARDRAIL_SCRIPT",
    "~/.openclaw/.skills/aport-guardrail.sh"
)

# ============================================================================
# VALIDATION PATTERNS
# ============================================================================

# Tool name validation pattern
TOOL_NAME_PATTERN = r"^[a-zA-Z0-9._-]+$"

# Agent ID validation pattern
AGENT_ID_PATTERN = r"^ap_[a-zA-Z0-9_]+$"

# Policy pack ID validation pattern
POLICY_PACK_ID_PATTERN = r"^[a-zA-Z0-9._-]+$"

# ============================================================================
# LOGGING
# ============================================================================

# Log level (DEBUG, INFO, WARN, ERROR)
LOG_LEVEL = os.environ.get("APORT_LOG_LEVEL", "INFO").upper()

# Log format (text, json)
LOG_FORMAT = os.environ.get("APORT_LOG_FORMAT", "text").lower()

# Enable debug unredacted logging (WARNING: exposes sensitive data)
DEBUG_UNREDACTED = os.environ.get("APORT_DEBUG_UNREDACTED", "0") == "1"

# Enable structured logging
STRUCTURED_LOGGING = os.environ.get("APORT_STRUCTURED_LOGGING", "0") == "1"

# ============================================================================
# SECURITY
# ============================================================================

# Fail open when missing configuration (legacy mode, not recommended)
FAIL_OPEN_WHEN_MISSING_CONFIG = os.environ.get("APORT_FAIL_OPEN_WHEN_MISSING_CONFIG", "0") in ("1", "true")

# Enable insecure TLS (development only, not recommended)
INSECURE_TLS = os.environ.get("APORT_INSECURE_TLS", "0") == "1"

# Sensitive field patterns for log redaction
SENSITIVE_FIELD_PATTERNS = [
    "password",
    "passwd",
    "pwd",
    "secret",
    "token",
    "key",
    "api",
    "bearer",
]

# API key prefix patterns for detection
API_KEY_PREFIXES = [
    "aprt_",  # APort API key
    "sk_",    # Secret key
    "pk_",    # Public key
]

# ============================================================================
# PERFORMANCE
# ============================================================================

# Enable performance monitoring
ENABLE_PERFORMANCE_MONITORING = os.environ.get("APORT_ENABLE_PERFORMANCE_MONITORING", "0") == "1"

# Slow operation threshold (milliseconds)
SLOW_OPERATION_THRESHOLD_MS = int(os.environ.get("APORT_SLOW_OPERATION_THRESHOLD_MS", "200"))

# ============================================================================
# FEATURE FLAGS
# ============================================================================

# Enable experimental features
ENABLE_EXPERIMENTAL_FEATURES = os.environ.get("APORT_ENABLE_EXPERIMENTAL", "0") == "1"

# Enable policy caching
ENABLE_POLICY_CACHING = os.environ.get("APORT_ENABLE_POLICY_CACHING", "1") == "1"

# Enable passport caching
ENABLE_PASSPORT_CACHING = os.environ.get("APORT_ENABLE_PASSPORT_CACHING", "1") == "1"

# ============================================================================
# TESTING
# ============================================================================

# Skip remote passport test in CI
SKIP_REMOTE_PASSPORT_TEST = os.environ.get("APORT_SKIP_REMOTE_PASSPORT_TEST", "0") == "1"

# Test mode (disables some security features)
TEST_MODE = os.environ.get("APORT_TEST_MODE", "0") == "1"

# ============================================================================
# VERSION
# ============================================================================

# APort specification version
OAP_SPEC_VERSION = "oap/1.0"

# Client library version (set by package)
CLIENT_VERSION = "1.0.8"

# ============================================================================
# MISC
# ============================================================================

# Decision file name pattern
DECISION_FILE_PATTERN = "decision-{pid}-{timestamp}.json"

# Audit log file name
AUDIT_LOG_FILENAME = "audit.log"

# Chain state file name
CHAIN_STATE_FILENAME = "chain-state.json"

# ============================================================================
# VALIDATION
# ============================================================================

def validate_constants() -> bool:
    """
    Validate that constants are within reasonable ranges.
    Raises ValueError if any constant is invalid.
    """
    # Validate positive integers
    if DEFAULT_SUBPROCESS_TIMEOUT <= 0:
        raise ValueError("DEFAULT_SUBPROCESS_TIMEOUT must be positive")

    if DEFAULT_API_TIMEOUT <= 0:
        raise ValueError("DEFAULT_API_TIMEOUT must be positive")

    if MAX_TOOL_NAME_LENGTH <= 0 or MAX_TOOL_NAME_LENGTH > 1000:
        raise ValueError("MAX_TOOL_NAME_LENGTH must be between 1 and 1000")

    if MAX_CONTEXT_SIZE_BYTES <= 0 or MAX_CONTEXT_SIZE_BYTES > 10 * 1024 * 1024:
        raise ValueError("MAX_CONTEXT_SIZE_BYTES must be between 1 and 10MB")

    if MAX_CONTEXT_NESTING_DEPTH <= 0 or MAX_CONTEXT_NESTING_DEPTH > 100:
        raise ValueError("MAX_CONTEXT_NESTING_DEPTH must be between 1 and 100")

    if DEFAULT_RATE_LIMIT_RPM <= 0 or DEFAULT_RATE_LIMIT_RPM > 100000:
        raise ValueError("DEFAULT_RATE_LIMIT_RPM must be between 1 and 100000")

    if MAX_API_RETRIES < 0 or MAX_API_RETRIES > 10:
        raise ValueError("MAX_API_RETRIES must be between 0 and 10")

    if API_RETRY_BACKOFF_MS <= 0:
        raise ValueError("API_RETRY_BACKOFF_MS must be positive")

    if PASSPORT_CACHE_TTL_SECONDS < 0:
        raise ValueError("PASSPORT_CACHE_TTL_SECONDS must be non-negative")

    # Validate log level
    if LOG_LEVEL not in ("DEBUG", "INFO", "WARN", "ERROR"):
        raise ValueError("LOG_LEVEL must be DEBUG, INFO, WARN, or ERROR")

    # Validate log format
    if LOG_FORMAT not in ("text", "json"):
        raise ValueError("LOG_FORMAT must be 'text' or 'json'")

    return True


# Run validation on import (can be disabled with APORT_SKIP_VALIDATION=1)
if os.environ.get("APORT_SKIP_VALIDATION", "0") != "1":
    validate_constants()
