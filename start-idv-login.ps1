<#
.SYNOPSIS
    Start IdentityV-login-helper and optionally configure an Android emulator proxy.
.DESCRIPTION
    This script is intended for a source checkout. It uses .venv, discovers a
    usable host IPv4 address, discovers ADB and connected Android devices, then
    starts the helper in process proxy mode.

    The script changes the selected Android device's global HTTP proxy unless
    -SkipProxy is specified. It does not read or write account credentials.
.PARAMETER OpenUI
    Open the channel-account management page after startup.
.PARAMETER SkipProxy
    Do not change an Android device proxy. Use this when the proxy is configured manually.
.PARAMETER ProxyPort
    Proxy port. Default: 10717.
.PARAMETER ProxyHost
    Host IPv4 address reachable from the emulator. If omitted, the script detects it.
.PARAMETER AdbPath
    Full path to adb.exe. If omitted, PATH and common MuMu locations are searched.
.PARAMETER DeviceSerial
    ADB serial to configure. If omitted, the only connected device is selected;
    multiple devices are presented for selection.
.PARAMETER ProxifyOnly
    Configure the selected Android device and exit without starting the helper.
.EXAMPLE
    .\start-idv-login.ps1
    .\start-idv-login.ps1 -OpenUI
    .\start-idv-login.ps1 -ProxyHost 192.168.1.20 -DeviceSerial 127.0.0.1:16384
    .\start-idv-login.ps1 -SkipProxy -ProxyHost 127.0.0.1
#>
[CmdletBinding()]
param(
    [switch]$OpenUI,
    [switch]$SkipProxy,
    [switch]$ProxifyOnly,
    [int]$ProxyPort = 10717,
    [string]$ProxyHost = '',
    [string]$AdbPath = '',
    [string]$DeviceSerial = ''
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$python = Join-Path $scriptDir '.venv\Scripts\python.exe'
$mainPy = Join-Path $scriptDir 'src\main.py'

function Step([string]$Text) { Write-Host "[*] $Text" -ForegroundColor Cyan }
function Good([string]$Text) { Write-Host "[+] $Text" -ForegroundColor Green }
function Warn([string]$Text) { Write-Host "[!] $Text" -ForegroundColor Yellow }
function Fail([string]$Text) { Write-Host "[x] $Text" -ForegroundColor Red }

if (-not (Test-Path -LiteralPath $python)) {
    Fail "Python virtual environment not found: $python"
    Write-Host 'Run: py -3.12 -m venv .venv; .\.venv\Scripts\python.exe -m pip install -r requirements.txt'
    exit 1
}
if (-not (Test-Path -LiteralPath $mainPy)) { Fail "Entry point not found: $mainPy"; exit 1 }
if ($ProxyPort -lt 1 -or $ProxyPort -gt 65535) { Fail "Invalid proxy port: $ProxyPort"; exit 1 }

if (-not $ProxyHost) {
    $addresses = @(Get-NetIPConfiguration -ErrorAction SilentlyContinue |
        Where-Object { $_.NetAdapter.Status -eq 'Up' -and $_.IPv4DefaultGateway } |
        ForEach-Object { $_.IPv4Address.IPAddress } |
        Where-Object { $_ -and $_ -notlike '127.*' -and $_ -notlike '169.254.*' } |
        Select-Object -Unique)
    if ($addresses.Count -eq 0) {
        Fail 'No usable IPv4 address found. Specify -ProxyHost with the host address reachable from the emulator.'
        exit 1
    }
    if ($addresses.Count -eq 1) {
        $ProxyHost = $addresses[0]
    } else {
        Write-Host 'Select the host IPv4 address reachable from the emulator:'
        for ($i = 0; $i -lt $addresses.Count; $i++) { Write-Host "[$($i + 1)] $($addresses[$i])" }
        $choice = Read-Host 'Enter a number or an IPv4 address'
        $number = 0
        if ([int]::TryParse($choice, [ref]$number) -and $number -ge 1 -and $number -le $addresses.Count) {
            $ProxyHost = $addresses[$number - 1]
        } else { $ProxyHost = $choice.Trim() }
    }
}
if ($ProxyHost -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
    Fail "Invalid IPv4 address: $ProxyHost"
    exit 1
}
Good "Proxy endpoint: ${ProxyHost}:$ProxyPort"

if (-not $AdbPath) {
    $adbCommand = Get-Command adb.exe, adb -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($adbCommand) { $AdbPath = $adbCommand.Source }
}
if (-not $AdbPath) {
    $adbCandidates = @(
        "$env:ProgramFiles\Netease\MuMuPlayer-12.0\nx_device\12.0\shell\adb.exe",
        "$env:ProgramFiles\Netease\MuMuPlayer-12.0\shell\adb.exe",
        "$env:ProgramFiles\Netease\MuMu\nx_device\12.0\shell\adb.exe"
    )
    $AdbPath = $adbCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if ($AdbPath -and -not (Test-Path -LiteralPath $AdbPath)) {
    Fail "ADB not found: $AdbPath"
    exit 1
}

if (-not $SkipProxy) {
    if (-not $AdbPath) {
        Warn 'ADB was not found; emulator proxy configuration was skipped. Use -AdbPath or -SkipProxy.'
    } else {
        $devices = @(& $AdbPath devices | Select-Object -Skip 1 |
            Where-Object { $_ -match '^\S+\s+device$' } |
            ForEach-Object { ($_ -split '\s+')[0] })
        if (-not $DeviceSerial) {
            if ($devices.Count -eq 1) {
                $DeviceSerial = $devices[0]
            } elseif ($devices.Count -gt 1) {
                Write-Host 'Select the Android device to configure:'
                for ($i = 0; $i -lt $devices.Count; $i++) { Write-Host "[$($i + 1)] $($devices[$i])" }
                $choice = Read-Host 'Enter a number or a device serial'
                $number = 0
                if ([int]::TryParse($choice, [ref]$number) -and $number -ge 1 -and $number -le $devices.Count) {
                    $DeviceSerial = $devices[$number - 1]
                } else { $DeviceSerial = $choice.Trim() }
            }
        }
        if (-not $DeviceSerial -or $devices -notcontains $DeviceSerial) {
            Warn 'No connected and authorized Android device selected; proxy configuration was skipped.'
        } else {
            Step "Configuring Android device $DeviceSerial..."
            & $AdbPath -s $DeviceSerial shell settings put global http_proxy "${ProxyHost}:$ProxyPort" | Out-Null
            $current = (& $AdbPath -s $DeviceSerial shell settings get global http_proxy 2>$null) -join ''
            if ($current.Trim() -eq "${ProxyHost}:$ProxyPort") {
                Good "Android proxy set to ${ProxyHost}:$ProxyPort"
            } else { Warn "Android proxy read-back: $current" }
        }
    }
}

if ($ProxifyOnly) { Good 'Proxy configuration finished.'; exit 0 }

$argsList = @($mainPy, '--proxy-mode', 'process', '--proxy-listen-host', $ProxyHost,
    '--proxy-port', [string]$ProxyPort)
if ($OpenUI) { $argsList += '--open-ui' }

Step 'Starting IdentityV-login-helper as administrator...'
$argLine = ($argsList | ForEach-Object { '"' + ($_ -replace '"','\"') + '"' }) -join ' '
$p = Start-Process -FilePath $python -ArgumentList $argLine -WorkingDirectory $scriptDir -Verb RunAs -PassThru
Good "Started, PID=$($p.Id)"
if ($OpenUI) { Good 'The account management page will open after startup.' }
