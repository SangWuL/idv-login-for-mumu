<#
.SYNOPSIS
    只启动 IdentityV-login-helper，不修改 MuMu 的代理设置。
.DESCRIPTION
    使用当前工作区的 .venv、源码入口和管理员权限启动工具。
    固定监听 192.168.1.21:10717，默认以 process 代理模式运行。
.PARAMETER OpenUI
    启动后立即打开渠道服账号管理页面。
.PARAMETER ProxyPort
    代理监听端口，默认 10717。
.EXAMPLE
    .\start-idv-login-only.ps1
    .\start-idv-login-only.ps1 -OpenUI
#>
[CmdletBinding()]
param(
    [switch]$OpenUI,
    [int]$ProxyPort = 10717
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$python    = Join-Path $scriptDir '.venv\Scripts\python.exe'
$mainPy    = Join-Path $scriptDir 'src\main.py'
$proxyHost = '192.168.1.21'

function Info([string]$Text) { Write-Host "[*] $Text" -ForegroundColor Cyan }
function Good([string]$Text) { Write-Host "[+] $Text" -ForegroundColor Green }
function Bad([string]$Text)  { Write-Host "[x] $Text" -ForegroundColor Red }

if (-not (Test-Path -LiteralPath $python)) { Bad "未找到虚拟环境 Python: $python"; exit 1 }
if (-not (Test-Path -LiteralPath $mainPy)) { Bad "未找到入口文件: $mainPy"; exit 1 }

$argsList = @(
    $mainPy,
    '--proxy-mode', 'process',
    '--proxy-listen-host', $proxyHost,
    '--proxy-port', [string]$ProxyPort
)
if ($OpenUI) { $argsList += '--open-ui' }

Info '以管理员权限启动 IdentityV-login-helper（不修改 MuMu 代理）...'
$argLine = ($argsList | ForEach-Object { '"' + ($_ -replace '"','\"') + '"' }) -join ' '
$p = Start-Process -FilePath $python -ArgumentList $argLine -WorkingDirectory $scriptDir -Verb RunAs -PassThru
Good "已启动，PID=$($p.Id)"
if ($OpenUI) { Good '管理页面将随工具启动后自动打开。' }
