<#
.SYNOPSIS
    Start IdentityV-login-helper without changing an Android device proxy.
.DESCRIPTION
    Uses the local .venv and source entry point. The proxy listens on an
    automatically detected host address so an emulator can reach it.
.PARAMETER OpenUI
    Open the channel-account management page after startup.
.PARAMETER ProxyPort
    Proxy port. Default: 10717.
.PARAMETER ProxyHost
    Host IPv4 address reachable from the emulator. If omitted, the script detects it.
.EXAMPLE
    .\start-idv-login-only.ps1
    .\start-idv-login-only.ps1 -OpenUI
    .\start-idv-login-only.ps1 -ProxyHost 127.0.0.1
#>
[CmdletBinding()]
param(
    [switch]$OpenUI,
    [int]$ProxyPort = 10717,
    [string]$ProxyHost = ''
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$python = Join-Path $scriptDir '.venv\Scripts\python.exe'
$mainPy = Join-Path $scriptDir 'src\main.py'
function Info([string]$Text) { Write-Host "[*] $Text" -ForegroundColor Cyan }
function Good([string]$Text) { Write-Host "[+] $Text" -ForegroundColor Green }
function Fail([string]$Text) { Write-Host "[x] $Text" -ForegroundColor Red }
if (-not (Test-Path -LiteralPath $python)) { Fail "Python virtual environment not found: $python"; exit 1 }
if (-not (Test-Path -LiteralPath $mainPy)) { Fail "Entry point not found: $mainPy"; exit 1 }
if (-not $ProxyHost) {
    $addresses = @(Get-NetIPConfiguration -ErrorAction SilentlyContinue |
        Where-Object { $_.NetAdapter.Status -eq 'Up' -and $_.IPv4DefaultGateway } |
        ForEach-Object { $_.IPv4Address.IPAddress } |
        Where-Object { $_ -and $_ -notlike '127.*' -and $_ -notlike '169.254.*' } |
        Select-Object -Unique)
    if ($addresses.Count -eq 0) { Fail 'No usable IPv4 address found. Use -ProxyHost.'; exit 1 }
    $ProxyHost = $addresses[0]
    if ($addresses.Count -gt 1) { Write-Host "Multiple addresses found; using $ProxyHost. Use -ProxyHost to override." -ForegroundColor Yellow }
}
if ($ProxyHost -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { Fail "Invalid IPv4 address: $ProxyHost"; exit 1 }
$argsList = @($mainPy, '--proxy-mode', 'process', '--proxy-listen-host', $ProxyHost, '--proxy-port', [string]$ProxyPort)
if ($OpenUI) { $argsList += '--open-ui' }
Info "Starting helper on ${ProxyHost}:$ProxyPort (Android proxy is not changed)..."
$argLine = ($argsList | ForEach-Object { '"' + ($_ -replace '"','\"') + '"' }) -join ' '
$p = Start-Process -FilePath $python -ArgumentList $argLine -WorkingDirectory $scriptDir -Verb RunAs -PassThru
Good "Started, PID=$($p.Id)"
