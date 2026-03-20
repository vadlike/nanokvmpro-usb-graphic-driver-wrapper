Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$releaseDir = Join-Path $repoRoot "release"
$packageName = "NanoKVMPro_USB_Graphic_Driver_Wrapper_v1.0.5"
$stageDir = Join-Path $env:TEMP ($packageName + "_" + [guid]::NewGuid().ToString())
$packageRoot = Join-Path $stageDir $packageName

New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null
New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null

Copy-Item `
    (Join-Path $repoRoot "README.md"), `
    (Join-Path $repoRoot "RELEASE_NOTES.md"), `
    (Join-Path $repoRoot "driver-tool.cmd"), `
    (Join-Path $repoRoot "nanokvm_usb_graphic.inf"), `
    (Join-Path $repoRoot "nanokvm_usb_graphic.cat"), `
    (Join-Path $repoRoot "nanokvm_usb_graphic.dll") `
    -Destination $packageRoot

$toolsDir = Join-Path $packageRoot "tools"
$certDir = Join-Path $packageRoot "cert"
$assetsDir = Join-Path $packageRoot "assets"

New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
New-Item -ItemType Directory -Path $certDir -Force | Out-Null
New-Item -ItemType Directory -Path $assetsDir -Force | Out-Null

Copy-Item (Join-Path $repoRoot "tools\driver-tool.ps1") -Destination $toolsDir
Copy-Item (Join-Path $repoRoot "tools\install-driver-elevated.ps1") -Destination $toolsDir
Copy-Item (Join-Path $repoRoot "tools\remove-driver-elevated.ps1") -Destination $toolsDir
Copy-Item (Join-Path $repoRoot "cert\nanokvm_usb_graphic-test.cer") -Destination $certDir
Copy-Item (Join-Path $repoRoot "assets\nanokvm-pro.png") -Destination $assetsDir

$zipPath = Join-Path $releaseDir ($packageName + ".zip")
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

& tar.exe -a -cf $zipPath -C $stageDir $packageName
if ($LASTEXITCODE -ne 0) {
    throw "Failed to build release archive."
}

$hash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash
$hashPath = Join-Path $releaseDir "SHA256SUMS.txt"
Set-Content -Path $hashPath -Encoding ASCII -Value ($hash + "  " + [IO.Path]::GetFileName($zipPath))

Remove-Item -LiteralPath $stageDir -Recurse -Force

Write-Host "Release package created:" -ForegroundColor Green
Write-Host $zipPath
Write-Host $hashPath
