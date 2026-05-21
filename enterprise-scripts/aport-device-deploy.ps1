# APort generic device install — Windows (PowerShell).
# Same variables as aport-device-deploy.sh. Requires Node.js, npm/npx, and curl.

#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ==============================================================================
# APORT DEVICE DEPLOYMENT - EDIT THIS SECTION ONLY
# ==============================================================================

if (-not $env:APORT_API_KEY) { $env:APORT_API_KEY = '' }
if (-not $env:APORT_TEMPLATE_ID) { $env:APORT_TEMPLATE_ID = '' }
if (-not $env:APORT_FRAMEWORK) { $env:APORT_FRAMEWORK = 'claude-code' }
if (-not $env:APORT_API_URL) { $env:APORT_API_URL = 'https://api.aport.io' }

# ==============================================================================
# NO CHANGES NEEDED BELOW THIS LINE
# ==============================================================================

$Core = Join-Path $PSScriptRoot 'aport-device-core.mjs'
if (-not (Test-Path -LiteralPath $Core)) {
    Write-Error "Missing $Core"
}
$env:APORT_DEVICE_COMMAND = 'install'
& node $Core install
exit $LASTEXITCODE
