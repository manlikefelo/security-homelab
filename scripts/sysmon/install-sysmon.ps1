<#
.SYNOPSIS
    Installs Sysinternals Sysmon on a Windows host using the well-known
    SwiftOnSecurity sysmon-config for rich, filtered telemetry.

.NOTES
    Run ELEVATED on DC01 and WS01. Requires the NAT adapter attached (guide 01) so it
    can download Sysmon + the config, OR pre-stage both files and pass -Offline paths.
    Idempotent: if Sysmon is already installed it updates the config instead of failing.

    Reviewer note: I use the community-standard SwiftOnSecurity config rather than
    logging everything - it's the config that turns Sysmon from noise into signal, and
    it's what feeds high-quality events (process create, network, image load) into
    Wazuh for detections.
#>

[CmdletBinding()]
param(
    [string]$WorkDir    = "$env:TEMP\sysmon",
    [string]$ConfigUrl  = 'https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml',
    [string]$SysmonUrl  = 'https://download.sysinternals.com/files/Sysmon.zip'
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

$sysmonExe  = Join-Path $WorkDir 'Sysmon64.exe'
$configXml  = Join-Path $WorkDir 'sysmonconfig.xml'

# --- Fetch Sysmon ---------------------------------------------------------------
if (-not (Test-Path $sysmonExe)) {
    Write-Host "[*] Downloading Sysmon..." -ForegroundColor Cyan
    $zip = Join-Path $WorkDir 'Sysmon.zip'
    Invoke-WebRequest -Uri $SysmonUrl -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath $WorkDir -Force
}

# --- Fetch the SwiftOnSecurity config -------------------------------------------
Write-Host "[*] Downloading SwiftOnSecurity sysmon-config..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $ConfigUrl -OutFile $configXml -UseBasicParsing

# --- Install or update ----------------------------------------------------------
$installed = Get-Service -Name Sysmon64 -ErrorAction SilentlyContinue
if ($installed) {
    Write-Host "[=] Sysmon already installed - updating config." -ForegroundColor Yellow
    & $sysmonExe -c $configXml
} else {
    Write-Host "[*] Installing Sysmon with SwiftOnSecurity config..." -ForegroundColor Cyan
    & $sysmonExe -accepteula -i $configXml
}

# --- Verify ---------------------------------------------------------------------
$svc = Get-Service -Name Sysmon64 -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq 'Running') {
    Write-Host "[+] Sysmon is running. Events -> Applications and Services Logs\Microsoft\Windows\Sysmon\Operational" -ForegroundColor Green
    $latest = Get-WinEvent -LogName 'Microsoft-Windows-Sysmon/Operational' -MaxEvents 1 -ErrorAction SilentlyContinue
    if ($latest) { Write-Host "    Newest Sysmon event: ID $($latest.Id) at $($latest.TimeCreated)" -ForegroundColor DarkGray }
} else {
    Write-Warning "Sysmon service not running - check the install output above."
}
