[CmdletBinding()]
param(
  [ValidateSet('lean')]
  [string]$Profile = 'lean',
  [switch]$InstallTools,
  [switch]$NoBuild,
  [switch]$Test,
  [ValidateSet('smoke', 'lean', 'all')]
  [string]$TestProfile,
  [string]$Report = '.zil/setup-report-windows.tsv'
)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $Root

function Test-Command([string]$Name) {
  return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-FirstLine([scriptblock]$Command) {
  try {
    $value = & $Command 2>&1 | Select-Object -First 1
    return [string]$value
  } catch {
    return $_.Exception.Message
  }
}

function Require-Command([string]$Name, [string]$Guidance) {
  if (-not (Test-Command $Name)) {
    throw "$Name is required. $Guidance"
  }
}

if (-not (Test-Command 'elan') -and $InstallTools) {
  Write-Host '[zil] installing Elan without a default global toolchain'
  $Installer = Join-Path $env:TEMP 'elan-init.ps1'
  Invoke-WebRequest -UseBasicParsing -Uri 'https://elan.lean-lang.org/elan-init.ps1' -OutFile $Installer
  & powershell -ExecutionPolicy Bypass -File $Installer -y --default-toolchain none
  Remove-Item $Installer -Force
  $env:Path = "$HOME\.elan\bin;$env:Path"
}

if ($Profile -eq 'lean') {
  Require-Command 'git' 'Install Git for Windows.'
  Require-Command 'curl' 'Install curl or use a current Windows release.'
  Require-Command 'elan' 'Run this script with -InstallTools or install Elan manually.'
  Require-Command 'lean' 'Ensure $HOME\.elan\bin is on PATH.'
  Require-Command 'lake' 'Ensure $HOME\.elan\bin is on PATH.'
}

if (-not $NoBuild) {
  & lake build
  if ($LASTEXITCODE -ne 0) { throw 'lake build failed' }
}

$ReportPath = if ([System.IO.Path]::IsPathRooted($Report)) { $Report } else { Join-Path $Root $Report }
$ReportDirectory = Split-Path -Parent $ReportPath
New-Item -ItemType Directory -Force -Path $ReportDirectory | Out-Null
$Rows = [System.Collections.Generic.List[string]]::new()
$Rows.Add('ZIL-SETUP-REPORT/1')
$Rows.Add("profile`t$Profile")
$Rows.Add("root`t$Root")
$Rows.Add("os`twindows")
$Rows.Add("build`t$(-not $NoBuild)")
if (Test-Command 'elan') { $Rows.Add("elan`t$(Get-FirstLine { elan --version })") }
if (Test-Command 'lean') { $Rows.Add("lean`t$(Get-FirstLine { lean --version })") }
if (Test-Command 'lake') { $Rows.Add("lake`t$(Get-FirstLine { lake --version })") }
$Rows.Add('result`tpass')
[System.IO.File]::WriteAllLines($ReportPath, $Rows)

$EnvPath = Join-Path $Root '.zil/setup.env.ps1'
@"
`$env:ZIL_HOME = '$Root'
`$env:Path = "`$HOME\.elan\bin;`$env:Path"
"@ | Set-Content -Path $EnvPath -Encoding UTF8

Write-Host "[zil] setup report: $ReportPath"
Write-Host "[zil] environment file: $EnvPath"

if ($Test) {
  if (-not $TestProfile) { $TestProfile = 'lean' }
  & (Join-Path $PSScriptRoot 'test.ps1') -Profile $TestProfile
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Host "[zil] setup complete for profile '$Profile'"
