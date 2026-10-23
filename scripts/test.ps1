[CmdletBinding()]
param(
  [ValidateSet('smoke', 'lean', 'all')]
  [string]$Profile = 'smoke',
  [string]$Report,
  [switch]$KeepWorkdir,
  [switch]$SkipBuild,
  [switch]$VerboseLogs
)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $Root

$Workdir = Join-Path ([System.IO.Path]::GetTempPath()) ("zil-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $Workdir | Out-Null

if (-not $Report) {
  $Report = Join-Path $Root ".zil/test-reports/$Profile-windows-latest.tsv"
} elseif (-not [System.IO.Path]::IsPathRooted($Report)) {
  $Report = Join-Path $Root $Report
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Report) | Out-Null
$Logs = "$Report.logs"
if (Test-Path $Logs) { Remove-Item -Recurse -Force $Logs }
New-Item -ItemType Directory -Force -Path $Logs | Out-Null

$script:Failures = 0
$script:Steps = 0
$script:Suite = ''
$script:BuildCompleted = $false
$Started = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$Rows = [System.Collections.Generic.List[string]]::new()
$Rows.Add('ZIL-TEST-REPORT/1')
$Rows.Add("profile`t$Profile")
$Rows.Add("root`t$Root")
$Rows.Add("workdir`t$Workdir")
$Rows.Add("logs`t$Logs")
$Rows.Add("started_epoch`t$Started")
$Rows.Add('step`tdescription`texpected`texit`tstatus`tduration_seconds`tlog`tcommand')

function Escape-Tsv([string]$Value) {
  return ($Value -replace "[`t`r`n]", ' ')
}

function Invoke-TestStep {
  param(
    [string]$Id,
    [string]$Description,
    [int[]]$Expected,
    [string]$Command,
    [object[]]$Arguments
  )
  $FullId = if ($script:Suite) { "$($script:Suite)-$Id" } else { $Id }
  $Log = Join-Path $Logs "$FullId.log"
  $Begin = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $script:Steps++
  Write-Host "[zil] [$FullId] $Description"
  try {
    & $Command @Arguments *> $Log
    $Exit = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
  } catch {
    $_ | Out-String | Add-Content -Path $Log
    $Exit = 2
  }
  $End = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $Status = if ($Expected -contains $Exit) { 'pass' } else { 'fail' }
  if ($Status -eq 'fail') {
    $script:Failures++
    Write-Warning "[$FullId] failed with exit $Exit; expected $($Expected -join ',')"
    if (Test-Path $Log) { Get-Content $Log -Tail 80 | Write-Host }
  } elseif ($VerboseLogs -and (Test-Path $Log)) {
    Get-Content $Log | Write-Host
  }
  $CommandText = "$Command " + (($Arguments | ForEach-Object { [string]$_ }) -join ' ')
  $Rows.Add((@(
    $FullId,
    (Escape-Tsv $Description),
    ($Expected -join ','),
    $Exit,
    $Status,
    ($End - $Begin),
    (Escape-Tsv $Log),
    (Escape-Tsv $CommandText)
  ) -join "`t"))
}

function Invoke-Doctor([string]$DoctorProfile) {
  $HostExe = (Get-Process -Id $PID).Path
  Invoke-TestStep 'doctor' "validate $DoctorProfile environment" @(0) $HostExe @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
    (Join-Path $PSScriptRoot 'setup.ps1'), '-Profile', $DoctorProfile,
    '-NoBuild', '-Report', (Join-Path $Workdir "doctor-$DoctorProfile.tsv")
  )
}

function Invoke-Build {
  if (-not $SkipBuild -and -not $script:BuildCompleted) {
    $Before = $script:Failures
    Invoke-TestStep 'lean-build' 'build Lean package' @(0) 'lake' @('build')
    if ($script:Failures -eq $Before) { $script:BuildCompleted = $true }
  }
}

function Invoke-LeanSuite {
  $script:Suite = 'lean'
  Invoke-Doctor 'lean'
  Invoke-Build
  Invoke-TestStep 'tests' 'run native Lean tests' @(0) 'lake' @('exe', 'zilLeanTests')
  $Generated = Join-Path $Workdir 'GeneratedAccess.lean'
  Invoke-TestStep 'compile' 'compile ZIL source to Lean' @(0) 'lake' @(
    'exe', 'zil', '--', 'compile', 'examples/authorization/access.zc',
    $Generated, 'Test.Install.GeneratedAccess'
  )
  Invoke-TestStep 'elaborate' 'elaborate generated Lean source' @(0) 'lake' @('env', 'lean', $Generated)
  Invoke-TestStep 'authorize' 'evaluate native authorization' @(0) 'lake' @(
    'exe', 'zil', '--', 'authorize', 'examples/authorization/access.zc',
    'doc:readme', 'viewer', 'user:11'
  )
  Invoke-TestStep 'impact' 'evaluate native impact' @(0) 'lake' @(
    'exe', 'zil', '--', 'impact', 'examples/impact/project.zc', 'lean:Parser.parse'
  )
}

function Invoke-SmokeSuite {
  $script:Suite = 'smoke'
  Invoke-Doctor 'lean'
  Invoke-Build
  Invoke-TestStep 'compile' 'compile checked-in source' @(0) 'lake' @(
    'exe', 'zil', '--', 'compile', 'examples/authorization/access.zc',
    (Join-Path $Workdir 'Smoke.lean'), 'Test.Smoke'
  )
  Invoke-TestStep 'authorize' 'run native authorization' @(0) 'lake' @(
    'exe', 'zil', '--', 'authorize', 'examples/authorization/access.zc',
    'doc:readme', 'viewer', 'user:11'
  )
}

switch ($Profile) {
  'smoke' { Invoke-SmokeSuite }
  'lean' { Invoke-LeanSuite }
  'all' { Invoke-LeanSuite }
}

$Finished = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$Rows.Add("finished_epoch`t$Finished")
$Rows.Add("duration_seconds`t$($Finished - $Started)")
$Rows.Add("steps`t$($script:Steps)")
$Rows.Add("failures`t$($script:Failures)")
$Rows.Add("result`t$(if ($script:Failures -eq 0) { 'pass' } else { 'fail' })")
[System.IO.File]::WriteAllLines($Report, $Rows)
Write-Host "[zil] test report: $Report"
Write-Host "[zil] step logs: $Logs"

if ($KeepWorkdir) {
  Write-Host "[zil] test workdir preserved: $Workdir"
} else {
  Remove-Item -Recurse -Force $Workdir
}

if ($script:Failures -eq 0) {
  Write-Host "[zil] profile '$Profile' passed ($($script:Steps) steps)"
  exit 0
}

Write-Warning "profile '$Profile' failed ($($script:Failures) of $($script:Steps) steps)"
exit 1
