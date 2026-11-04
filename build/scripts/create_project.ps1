param(
 [string]$VivadoBin='D:\Workapps\Vivado2025.2\2025.2\Vivado\bin',
 [switch]$Synthesize,
 [switch]$Implement,
 [string]$LoPin="U20",
 [string]$MonitorPin="V20"
)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$taskBuild=Join-Path $env:TEMP ('aux_pzt_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
if(Test-Path -LiteralPath $taskBuild){throw 'Temporary build folder already exists'}
[void](New-Item -ItemType Directory -Path $taskBuild)
foreach($taskFolder in @('src','sim','host')) {
 Copy-Item -LiteralPath (Join-Path $taskRoot $taskFolder) -Destination $taskBuild -Recurse
}
[void](New-Item -ItemType Directory -Path (Join-Path $taskBuild 'build'))
Copy-Item -LiteralPath $PSScriptRoot -Destination (Join-Path $taskBuild 'build') -Recurse
[void](New-Item -ItemType Directory -Path (Join-Path $taskBuild 'build/reports'))
[void](New-Item -ItemType Directory -Path (Join-Path $taskRoot 'build/reports') -Force)
$taskPreviousRoot=$env:AUX_PZT_BUILD_ROOT
$taskPreviousLoPin=$env:MIXER_LO_PIN
$taskPreviousMonPin=$env:MIXER_LO_MONITOR_PIN
$env:MIXER_LO_PIN=$LoPin
$env:MIXER_LO_MONITOR_PIN=$MonitorPin
try {
 $env:AUX_PZT_BUILD_ROOT=$taskBuild.Replace('\','/')
 $taskArgs=@('-mode','batch','-source',(Join-Path $taskBuild 'build/scripts/create_project.tcl'))
 if($Implement){$taskArgs+=@('-tclargs','-implement')} elseif($Synthesize){$taskArgs+=@('-tclargs','-synth')}
 Push-Location $taskBuild
 try {& (Join-Path $VivadoBin 'vivado.bat') @taskArgs *> (Join-Path $taskBuild 'build/reports/build.log')}
 finally {Pop-Location}
 $taskExit=$LASTEXITCODE
 $taskLog=Get-Content -LiteralPath (Join-Path $taskBuild 'build/reports/build.log') -Raw
 if($taskExit -ne 0 -or $taskLog -notmatch 'PROJECT_READY:'){throw "Project creation failed. Inspect $taskBuild/build/reports/build.log"}
 if($Synthesize -and $taskLog -notmatch 'SYNTHESIS_PASSED'){throw "Synthesis did not finish. Inspect $taskBuild/build/reports/build.log"}
 if($Implement -and $taskLog -notmatch 'IMPLEMENTATION_PASSED'){throw 'Implementation did not finish'}
 if(Test-Path -LiteralPath (Join-Path $taskBuild 'bitstream')){Copy-Item -LiteralPath (Join-Path $taskBuild 'bitstream') -Destination $taskRoot -Recurse -Force}
 Copy-Item -LiteralPath (Join-Path $taskBuild 'vivado_project') -Destination $taskRoot -Recurse -Force
 Copy-Item -LiteralPath (Join-Path $taskBuild 'src/constraints/lo_frequency.xdc') -Destination (Join-Path $taskRoot 'src/constraints/lo_frequency.xdc') -Force
 Get-ChildItem -LiteralPath (Join-Path $taskBuild 'build/reports') -File | ForEach-Object {
  Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $taskRoot 'build/reports') -Force
 }
 Write-Output (Join-Path $taskRoot 'vivado_project\aux_pzt_pi2d_lock.xpr')
} finally {$env:AUX_PZT_BUILD_ROOT=$taskPreviousRoot;$env:MIXER_LO_PIN=$taskPreviousLoPin;$env:MIXER_LO_MONITOR_PIN=$taskPreviousMonPin}
