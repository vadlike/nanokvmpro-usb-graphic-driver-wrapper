param(
    [ValidateSet("help", "status", "extract-cert", "create-cert", "trust-cert", "sign", "install", "remove", "full")]
    [string]$Action = "help",
    [string]$DriverDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [string]$InfName = "nanokvm_usb_graphic.inf",
    [string]$CatName = "nanokvm_usb_graphic.cat",
    [string]$DllName = "nanokvm_usb_graphic.dll",
    [string]$CertSubject = "CN=NanoKVM USB Graphic Test",
    [string]$CertThumbprint,
    [string]$CerPath,
    [string]$PfxPath,
    [string]$PfxPassword,
    [string]$TimestampUrl,
    [string]$OsList = "10_X64,Server10_X64,11_X64",
    [switch]$MachineStore,
    [switch]$UseExistingSigner,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "[*] $Message" -ForegroundColor Cyan
}

function Write-Note {
    param([string]$Message)
    Write-Host "[+] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Warning $Message
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Administrator {
    if (-not (Test-IsAdministrator)) {
        throw "This action requires an elevated PowerShell session."
    }
}

function Resolve-DriverFile {
    param([string]$Name)

    $path = Join-Path $DriverDir $Name
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required file not found: $path"
    }

    return (Resolve-Path -LiteralPath $path).Path
}

function Ensure-Directory {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        $null = New-Item -ItemType Directory -Path $Path -Force
    }

    return (Resolve-Path -LiteralPath $Path).Path
}

function Get-ArtifactPaths {
    $infPath = Resolve-DriverFile -Name $InfName
    $catPath = Join-Path $DriverDir $CatName
    $dllPath = Resolve-DriverFile -Name $DllName

    return [pscustomobject]@{
        Inf = $infPath
        Cat = $catPath
        Dll = $dllPath
    }
}

function Get-CertOutputDirectory {
    return Ensure-Directory -Path (Join-Path $DriverDir "cert")
}

function Get-ExistingSignerCertificate {
    $packagedCertificatePath = Get-PackagedCertificatePath
    if ($packagedCertificatePath) {
        return Get-CertificateFromFile -Path $packagedCertificatePath
    }

    throw "No signer certificate file was found in the current driver package. Expected one in the cert folder."
}

function Get-PackagedCertificatePath {
    $candidates = @(
        (Join-Path $DriverDir "cert\trusted-driver-signer.cer"),
        (Join-Path $DriverDir "cert\nanokvm_usb_graphic-test.cer"),
        (Join-Path $DriverDir "cert\existing-driver-signer.cer")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    return $null
}

function Get-SignatureVerification {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Signature target not found: $Path"
    }

    $signToolPath = Find-SignTool
    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    $stdoutPath = Join-Path $env:TEMP ("nanokvm-signtool-{0}.out.txt" -f [guid]::NewGuid())
    $stderrPath = Join-Path $env:TEMP ("nanokvm-signtool-{0}.err.txt" -f [guid]::NewGuid())

    try {
        $process = Start-Process -FilePath $signToolPath `
            -ArgumentList @("verify", "/pa", "/v", $resolvedPath) `
            -NoNewWindow `
            -Wait `
            -PassThru `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath

        $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { "" }
        $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { "" }
        $output = ($stdout + [Environment]::NewLine + $stderr).Trim()
        $exitCode = $process.ExitCode
    } finally {
        Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
    }

    $subject = $null
    $thumbprint = $null

    if ($output -match "Issued to:\s*(.+)") {
        $subject = $Matches[1].Trim()
    }

    if ($output -match "SHA1 hash:\s*([0-9A-F]+)") {
        $thumbprint = $Matches[1].Trim()
    }

    $status = if ($exitCode -eq 0) {
        "Valid"
    } elseif ($output -match "not trusted") {
        "Untrusted"
    } else {
        "Invalid"
    }

    $message = $null
    if ($output -match "SignTool Error:\s*(.+)") {
        $message = $Matches[1].Trim()
    }

    return [pscustomobject]@{
        Status = $status
        StatusMessage = $message
        Subject = $subject
        Thumbprint = $thumbprint
    }
}

function Export-CertificateFile {
    param(
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [string]$OutputPath
    )

    $null = Export-Certificate -Cert $Certificate -FilePath $OutputPath -Force
    return (Resolve-Path -LiteralPath $OutputPath).Path
}

function Get-CertificateFromFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Certificate file not found: $Path"
    }

    return [System.Security.Cryptography.X509Certificates.X509Certificate2]::new((Resolve-Path -LiteralPath $Path).Path)
}

function Find-CodeSigningCertificate {
    param(
        [string]$Subject,
        [string]$Thumbprint
    )

    $stores = @(
        @{ Path = "Cert:\LocalMachine\My"; Machine = $true },
        @{ Path = "Cert:\CurrentUser\My"; Machine = $false }
    )

    foreach ($store in $stores) {
        if (-not (Test-Path -LiteralPath $store.Path)) {
            continue
        }

        $matches = Get-ChildItem -LiteralPath $store.Path |
            Where-Object {
                $_.HasPrivateKey -and
                (
                    ($Thumbprint -and $_.Thumbprint -eq $Thumbprint) -or
                    (-not $Thumbprint -and $_.Subject -eq $Subject)
                )
            } |
            Sort-Object NotAfter -Descending

        if ($matches) {
            return [pscustomobject]@{
                Certificate = $matches[0]
                UseMachineStore = $store.Machine
            }
        }
    }

    return $null
}

function New-CodeSigningCertificate {
    if ($MachineStore) {
        Assert-Administrator
    }

    $existing = Find-CodeSigningCertificate -Subject $CertSubject -Thumbprint $CertThumbprint
    if ($existing -and -not $Force) {
        Write-Note "Using existing certificate $($existing.Certificate.Subject) [$($existing.Certificate.Thumbprint)]"
        return $existing
    }

    $storeLocation = if ($MachineStore) { "Cert:\LocalMachine\My" } else { "Cert:\CurrentUser\My" }
    Write-Step "Creating self-signed code-signing certificate in $storeLocation"

    $certificate = New-SelfSignedCertificate `
        -Type CodeSigningCert `
        -Subject $CertSubject `
        -CertStoreLocation $storeLocation `
        -KeyExportPolicy Exportable `
        -HashAlgorithm sha256 `
        -NotAfter (Get-Date).AddYears(5)

    $outputDir = Get-CertOutputDirectory
    $defaultCerPath = Join-Path $outputDir "nanokvm_usb_graphic-test.cer"
    $resolvedCerPath = Export-CertificateFile -Certificate $certificate -OutputPath $defaultCerPath
    Write-Note "Public certificate exported to $resolvedCerPath"

    if ($PfxPath -or $PfxPassword) {
        $targetPfx = if ($PfxPath) { $PfxPath } else { Join-Path $outputDir "nanokvm_usb_graphic-test.pfx" }
        if (-not $PfxPassword) {
            throw "PfxPassword is required when exporting a PFX."
        }

        $securePassword = ConvertTo-SecureString -String $PfxPassword -AsPlainText -Force
        $null = Export-PfxCertificate -Cert $certificate -FilePath $targetPfx -Password $securePassword -Force
        Write-Note "PFX exported to $targetPfx"
    }

    return [pscustomobject]@{
        Certificate = $certificate
        UseMachineStore = $MachineStore.IsPresent
    }
}

function Get-OrCreateCertificateForSigning {
    if ($UseExistingSigner) {
        throw "UseExistingSigner installs the current package as-is. Re-signing requires your own certificate."
    }

    $existing = Find-CodeSigningCertificate -Subject $CertSubject -Thumbprint $CertThumbprint
    if ($existing) {
        return $existing
    }

    return New-CodeSigningCertificate
}

function Get-CertificateToTrust {
    if ($CerPath) {
        return Get-CertificateFromFile -Path $CerPath
    }

    if ($UseExistingSigner) {
        return Get-ExistingSignerCertificate
    }

    $existing = Find-CodeSigningCertificate -Subject $CertSubject -Thumbprint $CertThumbprint
    if ($existing) {
        return $existing.Certificate
    }

    $created = New-CodeSigningCertificate
    return $created.Certificate
}

function Test-CertificateTrusted {
    param([System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)

    return Test-CertificateTrustedByThumbprint -Thumbprint $Certificate.Thumbprint
}

function Test-CertificateTrustedByThumbprint {
    param([string]$Thumbprint)

    $normalizedThumbprint = $Thumbprint.ToUpperInvariant()
    $rootStore = [System.Security.Cryptography.X509Certificates.X509Store]::new(
        [System.Security.Cryptography.X509Certificates.StoreName]::Root,
        [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
    )
    $publisherStore = [System.Security.Cryptography.X509Certificates.X509Store]::new(
        [System.Security.Cryptography.X509Certificates.StoreName]::TrustedPublisher,
        [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
    )

    try {
        $rootStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
        $publisherStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)

        $inRoot = @($rootStore.Certificates | Where-Object { $_.Thumbprint.ToUpperInvariant() -eq $normalizedThumbprint }).Count -gt 0
        $inPublisher = @($publisherStore.Certificates | Where-Object { $_.Thumbprint.ToUpperInvariant() -eq $normalizedThumbprint }).Count -gt 0
    } finally {
        $rootStore.Close()
        $publisherStore.Close()
    }

    return [pscustomobject]@{
        InRoot = $inRoot
        InTrustedPublisher = $inPublisher
    }
}

function Import-CertificateToTrustStores {
    param([System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)

    Assert-Administrator

    $outputDir = Get-CertOutputDirectory
    $path = if ($CerPath) {
        (Resolve-Path -LiteralPath $CerPath).Path
    } else {
        Export-CertificateFile -Certificate $Certificate -OutputPath (Join-Path $outputDir "trusted-driver-signer.cer")
    }

    Write-Step "Importing certificate into LocalMachine\\Root"
    $null = Import-Certificate -FilePath $path -CertStoreLocation "Cert:\LocalMachine\Root"

    Write-Step "Importing certificate into LocalMachine\\TrustedPublisher"
    $null = Import-Certificate -FilePath $path -CertStoreLocation "Cert:\LocalMachine\TrustedPublisher"

    Write-Note "Trusted certificate: $($Certificate.Subject) [$($Certificate.Thumbprint)]"
}

function Invoke-ExternalCommand {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )

    Write-Step ("Running: {0} {1}" -f $FilePath, ($Arguments -join " "))
    & $FilePath @Arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Command failed with exit code ${exitCode}: $FilePath"
    }
}

function Find-SignTool {
    $direct = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($direct) {
        return $direct.Source
    }

    $kitRoot = "C:\Program Files (x86)\Windows Kits\10\bin"
    if (-not (Test-Path -LiteralPath $kitRoot)) {
        throw "signtool.exe not found. Install the Windows SDK."
    }

    $candidates = Get-ChildItem -LiteralPath $kitRoot -Recurse -Filter signtool.exe -File |
        Where-Object { $_.FullName -match "\\x64\\signtool\.exe$" } |
        Sort-Object FullName -Descending

    if ($candidates) {
        return $candidates[0].FullName
    }

    $ackTool = "C:\Program Files (x86)\Windows Kits\10\App Certification Kit\signtool.exe"
    if (Test-Path -LiteralPath $ackTool) {
        return $ackTool
    }

    throw "signtool.exe not found. Install the Windows SDK."
}

function Find-Inf2Cat {
    $direct = Get-Command Inf2Cat.exe -ErrorAction SilentlyContinue
    if ($direct) {
        return $direct.Source
    }

    $kitRoot = "C:\Program Files (x86)\Windows Kits\10\bin"
    if (-not (Test-Path -LiteralPath $kitRoot)) {
        return $null
    }

    $candidates = Get-ChildItem -LiteralPath $kitRoot -Recurse -Filter Inf2Cat.exe -File |
        Where-Object { $_.FullName -match "\\x64\\Inf2Cat\.exe$" } |
        Sort-Object FullName -Descending

    if ($candidates) {
        return $candidates[0].FullName
    }

    return $null
}

function Find-MakeCat {
    $direct = Get-Command makecat.exe -ErrorAction SilentlyContinue
    if ($direct) {
        return $direct.Source
    }

    $kitRoot = "C:\Program Files (x86)\Windows Kits\10\bin"
    if (-not (Test-Path -LiteralPath $kitRoot)) {
        return $null
    }

    $candidates = Get-ChildItem -LiteralPath $kitRoot -Recurse -Filter makecat.exe -File |
        Where-Object { $_.FullName -match "\\x64\\makecat\.exe$" } |
        Sort-Object FullName -Descending

    if ($candidates) {
        return $candidates[0].FullName
    }

    return $null
}

function Get-SignToolCertificateArguments {
    if ($PfxPath) {
        if (-not (Test-Path -LiteralPath $PfxPath)) {
            throw "PFX file not found: $PfxPath"
        }

        $arguments = @("/f", (Resolve-Path -LiteralPath $PfxPath).Path)
        if ($PfxPassword) {
            $arguments += @("/p", $PfxPassword)
        }

        return $arguments
    }

    $certificateInfo = Get-OrCreateCertificateForSigning
    $arguments = @("/sha1", $certificateInfo.Certificate.Thumbprint)

    if ($certificateInfo.UseMachineStore) {
        $arguments += "/sm"
    }

    return $arguments
}

function Sign-File {
    param(
        [string]$TargetPath,
        [string]$SignToolPath,
        [string[]]$CertificateArguments
    )

    if (-not (Test-Path -LiteralPath $TargetPath)) {
        throw "File to sign not found: $TargetPath"
    }

    $arguments = @("sign", "/fd", "SHA256")
    if ($TimestampUrl) {
        $arguments += @("/tr", $TimestampUrl, "/td", "SHA256")
    }

    $arguments += $CertificateArguments
    $arguments += (Resolve-Path -LiteralPath $TargetPath).Path

    Invoke-ExternalCommand -FilePath $SignToolPath -Arguments $arguments
}

function Rebuild-Catalog {
    $inf2CatPath = Find-Inf2Cat
    if ($inf2CatPath) {
        Write-Step "Rebuilding catalog from INF and current package files with Inf2Cat"
        $arguments = @("/driver:$DriverDir", "/os:$OsList", "/verbose")
        Invoke-ExternalCommand -FilePath $inf2CatPath -Arguments $arguments
        return
    }

    $makeCatPath = Find-MakeCat
    if (-not $makeCatPath) {
        throw "Neither Inf2Cat.exe nor makecat.exe was found. Install the WDK or Windows SDK catalog tools."
    }

    $artifacts = Get-ArtifactPaths
    $cdfPath = Join-Path $DriverDir "nanokvm_usb_graphic.cdf"
    $catPath = Join-Path $DriverDir $CatName
    $infRelativePath = Split-Path -Leaf $artifacts.Inf
    $dllRelativePath = Split-Path -Leaf $artifacts.Dll

    $cdfContent = @"
[CatalogHeader]
Name=$CatName
PublicVersion=0x0000001
EncodingType=0x00010001
CATATTR1=0x10010001:OSAttr:2:10.0

[CatalogFiles]
<hash>File1=$infRelativePath
<hash>File2=$dllRelativePath
"@

    Set-Content -LiteralPath $cdfPath -Value $cdfContent -Encoding ASCII

    if (Test-Path -LiteralPath $catPath) {
        Remove-Item -LiteralPath $catPath -Force
    }

    Write-Warn "Inf2Cat.exe not found. Falling back to makecat.exe for a test-signing catalog."
    $currentLocation = Get-Location
    try {
        Set-Location -LiteralPath $DriverDir
        Invoke-ExternalCommand -FilePath $makeCatPath -Arguments @("-v", (Split-Path -Leaf $cdfPath))
    } finally {
        Set-Location -LiteralPath $currentLocation
    }
}

function Show-Status {
    $artifacts = Get-ArtifactPaths

    Write-Host ""
    Write-Host "Driver package:" -ForegroundColor Yellow
    Write-Host "  INF: $($artifacts.Inf)"
    Write-Host "  DLL: $($artifacts.Dll)"
    Write-Host "  CAT: $($artifacts.Cat)"

    foreach ($path in @($artifacts.Dll, $artifacts.Cat)) {
        Write-Host ""
        Write-Host $path -ForegroundColor Yellow
        if (-not (Test-Path -LiteralPath $path)) {
            Write-Host "  Missing"
            continue
        }

        $signature = Get-SignatureVerification -Path $path
        Write-Host "  Status: $($signature.Status)"
        if ($signature.StatusMessage) {
            Write-Host "  Message: $($signature.StatusMessage)"
        }

        if ($signature.Subject) {
            Write-Host "  Subject: $($signature.Subject)"
            Write-Host "  Thumbprint: $($signature.Thumbprint)"
            $trusted = Test-CertificateTrustedByThumbprint -Thumbprint $signature.Thumbprint
            Write-Host "  Trusted Root: $($trusted.InRoot)"
            Write-Host "  Trusted Publisher: $($trusted.InTrustedPublisher)"
        } else {
            Write-Host "  Signer certificate: not present"
        }
    }

    Write-Host ""
    Write-Host "Tools:" -ForegroundColor Yellow
    Write-Host "  signtool.exe: $(Find-SignTool)"
    $inf2CatPath = Find-Inf2Cat
    Write-Host "  Inf2Cat.exe: $(if ($inf2CatPath) { $inf2CatPath } else { 'not found' })"
    $makeCatPath = Find-MakeCat
    Write-Host "  makecat.exe: $(if ($makeCatPath) { $makeCatPath } else { 'not found' })"
}

function Extract-ExistingSignerCertificate {
    $certificate = Get-ExistingSignerCertificate
    $outputDir = Get-CertOutputDirectory
    $targetPath = if ($CerPath) { $CerPath } else { Join-Path $outputDir "existing-driver-signer.cer" }
    $resolved = Export-CertificateFile -Certificate $certificate -OutputPath $targetPath
    Write-Note "Existing signer certificate exported to $resolved"
}

function Install-DriverPackage {
    Assert-Administrator

    $artifacts = Get-ArtifactPaths
    $arguments = @("/add-driver", $artifacts.Inf, "/install")
    Invoke-ExternalCommand -FilePath "pnputil.exe" -Arguments $arguments
}

function Get-DriverStorePublishedNames {
    $enumOutput = pnputil /enum-drivers
    $publishedNames = New-Object System.Collections.Generic.List[string]
    $currentPublishedName = $null
    $currentOriginalName = $null

    foreach ($line in $enumOutput) {
        if ($line -match '^\s*Published Name:\s*(.+)$') {
            $currentPublishedName = $Matches[1].Trim()
            $currentOriginalName = $null
            continue
        }

        if ($line -match '^\s*Original Name:\s*(.+)$') {
            $currentOriginalName = $Matches[1].Trim()
            if ($currentPublishedName -and $currentOriginalName -ieq $InfName) {
                $publishedNames.Add($currentPublishedName)
            }
        }
    }

    return @($publishedNames | Select-Object -Unique)
}

function Get-NanoKvmDeviceInstanceIds {
    $devices = Get-PnpDevice | Where-Object {
        $_.InstanceId -like 'USB\VID_3346&PID_1009*' -or
        $_.FriendlyName -like '*NanoKVM*'
    }

    return @($devices | Select-Object -ExpandProperty InstanceId -Unique)
}

function Remove-DriverPackage {
    Assert-Administrator

    $instanceIds = Get-NanoKvmDeviceInstanceIds
    foreach ($instanceId in $instanceIds) {
        Write-Step "Removing device $instanceId"
        & pnputil.exe /remove-device $instanceId
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Device removal returned exit code $LASTEXITCODE for $instanceId"
        }
    }

    $publishedNames = Get-DriverStorePublishedNames
    foreach ($publishedName in $publishedNames) {
        Write-Step "Deleting driver package $publishedName from the driver store"
        & pnputil.exe /delete-driver $publishedName /uninstall /force
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Driver package deletion returned exit code $LASTEXITCODE for $publishedName"
        }
    }

    Write-Step "Rescanning devices"
    & pnputil.exe /scan-devices
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Device rescan returned exit code $LASTEXITCODE"
    }
}

function Sign-DriverPackage {
    $artifacts = Get-ArtifactPaths
    $signToolPath = Find-SignTool
    $certificateArguments = Get-SignToolCertificateArguments

    # The catalog must be generated from the final DLL bytes, so the DLL is signed first.
    Sign-File -TargetPath $artifacts.Dll -SignToolPath $signToolPath -CertificateArguments $certificateArguments
    Rebuild-Catalog
    Sign-File -TargetPath $artifacts.Cat -SignToolPath $signToolPath -CertificateArguments $certificateArguments

    Write-Note "Driver package signed successfully."
}

function Invoke-FullWorkflow {
    if ($UseExistingSigner) {
        Write-Step "Trusting the current package signer and installing without modifying package files"
        $certificate = Get-CertificateToTrust
        Import-CertificateToTrustStores -Certificate $certificate
        Install-DriverPackage
        return
    }

    Write-Step "Creating or reusing a local code-signing certificate"
    $certificateInfo = Get-OrCreateCertificateForSigning

    Write-Step "Trusting the signing certificate"
    Import-CertificateToTrustStores -Certificate $certificateInfo.Certificate

    Write-Step "Signing driver files and rebuilding the catalog"
    Sign-DriverPackage

    Write-Step "Installing the driver package"
    Install-DriverPackage
}

switch ($Action) {
    "help" {
        @"
Usage:
  .\tools\driver-tool.ps1 -Action status
  .\tools\driver-tool.ps1 -Action full -UseExistingSigner
  .\tools\driver-tool.ps1 -Action full -MachineStore -CertSubject "CN=NanoKVM USB Graphic Test"
  .\tools\driver-tool.ps1 -Action sign -MachineStore -TimestampUrl "http://timestamp.digicert.com"

Actions:
  status        Show package signature status and available tooling.
  extract-cert  Export the signer certificate from the current package.
  create-cert   Create a new self-signed code-signing certificate.
  trust-cert    Import a certificate into Root and TrustedPublisher.
  sign          Sign the DLL, rebuild the CAT with Inf2Cat, sign the CAT.
  install       Install the INF package with pnputil.
  remove        Remove NanoKVM driver devices and delete matching OEM packages from the driver store.
  full          Complete workflow. With -UseExistingSigner it trusts the current package signer and installs as-is.

Notes:
  - trust-cert, install and full require an elevated PowerShell session.
  - sign uses Inf2Cat.exe when available and falls back to makecat.exe for a test-signing catalog.
  - Use -UseExistingSigner when you only need to trust the current WDK test certificate and install the package.
"@ | Write-Host
    }
    "status" {
        Show-Status
    }
    "extract-cert" {
        Extract-ExistingSignerCertificate
    }
    "create-cert" {
        $certificateInfo = New-CodeSigningCertificate
        Write-Note "Certificate ready: $($certificateInfo.Certificate.Subject) [$($certificateInfo.Certificate.Thumbprint)]"
    }
    "trust-cert" {
        $certificate = Get-CertificateToTrust
        Import-CertificateToTrustStores -Certificate $certificate
    }
    "sign" {
        Sign-DriverPackage
    }
    "install" {
        Install-DriverPackage
    }
    "remove" {
        Remove-DriverPackage
    }
    "full" {
        Invoke-FullWorkflow
    }
}
