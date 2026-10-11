<#
.SYNOPSIS
    启动 IdentityV-login-helper，并可选配置 MuMu 实例的 HTTP 代理。
.DESCRIPTION
    该脚本面向当前工作区源码运行，会自动：
      1. 检查/使用 .venv 中的 Python；
      2. 校验代理监听地址与端口；
      3. 提示并可选把 MuMu(雪之莹) 的全局代理指向本机；
      4. 以管理员权限启动工具，保证代理/DNS/hosts 配置可生效。

    不写入任何账号或登录凭证；仅在需要时修改 MuMu 的全局 http_proxy 设置。
.PARAMETER OpenUI
    启动后立即打开渠道服账号管理页面。
.PARAMETER SkipProxy
    不自动配置 MuMu 的全局代理，只启动工具。
.PARAMETER ProxyPort
    代理监听端口，默认 10717。
.PARAMETER ProxifyOnly
    只配置 MuMu 代理并退出，不启动工具（用于单独修复代理）。
.EXAMPLE
    .\start-idv-login.ps1
    .\start-idv-login.ps1 -OpenUI
    .\start-idv-login.ps1 -ProxifyOnly
#>
[CmdletBinding()]
param(
    [switch]$OpenUI,
    [switch]$SkipProxy,
    [switch]$ProxifyOnly,
    [int]$ProxyPort = 10717
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$python      = Join-Path $scriptDir '.venv\Scripts\python.exe'
$mainPy      = Join-Path $scriptDir 'src\main.py'
$adb         = 'D:\Program Files\Netease\MuMu\nx_device\12.0\shell\adb.exe'
$mumuSerial  = '192.168.1.122:5555'
$proxyHost   = '192.168.1.21'

function Write-Step([string]$Text) { Write-Host "[*] $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text)   { Write-Host "[+] $Text" -ForegroundColor Green }
function Write-Warn([string]$Text) { Write-Host "[!] $Text" -ForegroundColor Yellow }
function Write-Err([string]$Text)  { Write-Host "[x] $Text" -ForegroundColor Red }

if (-not (Test-Path -LiteralPath $python)) { Write-Err "未找到虚拟环境 Python: $python"; exit 1 }
if (-not (Test-Path -LiteralPath $mainPy)) { Write-Err "未找到入口文件: $mainPy"; exit 1 }

$ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
      Where-Object {
          $_.IPAddress -eq $proxyHost -and
          $_.AddressState -eq 'Preferred' -and
          $_.PrefixOrigin -ne 'WellKnown'
      } | Select-Object -First 1
if (-not $ip) {
    Write-Warn "未在当前机器上找到地址 $proxyHost；如果热点/网段已变化，请用 -ProxyHost 修改脚本内变量。"
} else {
    Write-Ok "代理监听地址: $proxyHost"
}

if (-not $SkipProxy) {
    if (-not (Test-Path -LiteralPath $adb)) {
        Write-Warn "未找到 MuMu adb: $adb，跳过 MuMu 代理配置。"
    } else {
        Write-Step '配置 MuMu(雪之莹) 全局 HTTP 代理...'
        & $adb -s $mumuSerial wait-for-device | Out-Null
        $live = (& $adb -s $mumuSerial get-state 2>$null) -join ''
        if ($live.Trim() -ne 'device') {
            Write-Warn "MuMu 设备 $mumuSerial 不可用（当前: $live），跳过代理配置。"
        } else {
            & $adb -s $mumuSerial shell settings put global http_proxy "${proxyHost}:$ProxyPort" | Out-Null
            $current = (& $adb -s $mumuSerial shell settings get global http_proxy 2>$null) -join ''
            if ($current.Trim() -eq "${proxyHost}:$ProxyPort") {
                Write-Ok "MuMu 代理已设置为 ${proxyHost}:$ProxyPort"
            } else {
                Write-Warn "MuMu 代理设置后回读为: $current"
            }
        }
    }
}

if ($ProxifyOnly) { Write-Ok '仅配置代理完成。'; exit 0 }

$argsList = @(
    $mainPy,
    '--proxy-mode', 'process',
    '--proxy-listen-host', $proxyHost,
    '--proxy-port', [string]$ProxyPort
)
if ($OpenUI) { $argsList += '--open-ui' }

Write-Step '以管理员权限启动 IdentityV-login-helper...'
$argLine = ($argsList | ForEach-Object { '"' + ($_ -replace '"','\"') + '"' }) -join ' '
$p = Start-Process -FilePath $python -ArgumentList $argLine -WorkingDirectory $scriptDir -Verb RunAs -PassThru
Write-Ok "已启动，PID=$($p.Id)"
if ($OpenUI) { Write-Ok '管理页面将随工具启动后自动打开。' }
Write-Host ''
Write-Host '接下来：在 MuMu 中打开阴阳师官服，工具会自动复用已保存的扫码记录。' -ForegroundColor Gray
