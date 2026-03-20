Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$toolPath = Join-Path $PSScriptRoot "driver-tool.ps1"
& $toolPath -Action remove
