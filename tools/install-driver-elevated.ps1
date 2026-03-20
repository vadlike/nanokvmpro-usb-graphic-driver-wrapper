Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$toolPath = Join-Path $PSScriptRoot "driver-tool.ps1"
$certPath = Join-Path (Join-Path $PSScriptRoot "..") "cert\nanokvm_usb_graphic-test.cer"

& $toolPath -Action trust-cert -CerPath $certPath
& $toolPath -Action install
