# APort generic device enforcement — Windows (PowerShell).

#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

if (-not $env:APORT_API_KEY) { $env:APORT_API_KEY = '' }
if (-not $env:APORT_TEMPLATE_ID) { $env:APORT_TEMPLATE_ID = '' }
if (-not $env:APORT_FRAMEWORK) { $env:APORT_FRAMEWORK = 'claude-code' }
if (-not $env:APORT_API_URL) { $env:APORT_API_URL = 'https://api.aport.io' }

$Core = Join-Path $PSScriptRoot 'aport-device-core.mjs'
$env:APORT_DEVICE_COMMAND = 'enforce'
& node $Core enforce
exit $LASTEXITCODE
