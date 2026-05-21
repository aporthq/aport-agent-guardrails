# APort generic device uninstall — Windows (PowerShell).

#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

if (-not $env:APORT_FRAMEWORK) { $env:APORT_FRAMEWORK = 'claude-code' }

$Core = Join-Path $PSScriptRoot 'aport-device-core.mjs'
$env:APORT_DEVICE_COMMAND = 'uninstall'
& node $Core uninstall
exit $LASTEXITCODE
