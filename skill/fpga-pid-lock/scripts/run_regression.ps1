param(
    [string]$ModelSimBin = "",
    [string]$WorkDir = "",
    [switch]$SkipLegacy
)

$ErrorActionPreference = "Stop"
$skillRoot = Split-Path -Parent $PSScriptRoot
$assets = Join-Path $skillRoot "assets"

if ([string]::IsNullOrWhiteSpace($ModelSimBin)) {
    $pathVlog = Get-Command "vlog.exe" -ErrorAction SilentlyContinue
    if ($pathVlog) {
        $ModelSimBin = Split-Path -Parent $pathVlog.Source
    } else {
        throw "ModelSim was not found. Pass -ModelSimBin <directory containing vlog.exe and vsim.exe>."
    }
}

$vlib = Join-Path $ModelSimBin "vlib.exe"
$vlog = Join-Path $ModelSimBin "vlog.exe"
$vsim = Join-Path $ModelSimBin "vsim.exe"
foreach ($tool in @($vlib, $vlog, $vsim)) {
    if (-not (Test-Path -LiteralPath $tool)) {
        throw "Missing simulator executable: $tool"
    }
}

if ([string]::IsNullOrWhiteSpace($WorkDir)) {
    $WorkDir = Join-Path ([IO.Path]::GetTempPath()) ("fpga_pid_lock_" + [guid]::NewGuid().ToString("N"))
}
$resolvedParent = [IO.Path]::GetFullPath((Split-Path -Parent $WorkDir))
if (-not (Test-Path -LiteralPath $resolvedParent)) {
    New-Item -ItemType Directory -Path $resolvedParent | Out-Null
}
$WorkDir = [IO.Path]::GetFullPath($WorkDir)
if (Test-Path -LiteralPath $WorkDir) {
    if ((Get-ChildItem -LiteralPath $WorkDir -Force | Measure-Object).Count -ne 0) {
        throw "WorkDir must be new or empty: $WorkDir"
    }
} else {
    New-Item -ItemType Directory -Path $WorkDir | Out-Null
}

function Invoke-Checked {
    param([string]$Exe, [string[]]$Arguments)
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$([IO.Path]::GetFileName($Exe)) failed with exit code $LASTEXITCODE"
    }
}

function Require-LogText {
    param([string]$LogPath, [string]$Expected)
    $text = Get-Content -Raw -LiteralPath $LogPath
    if ($text -notmatch [regex]::Escape($Expected)) {
        throw "Expected marker not found in $LogPath : $Expected"
    }
    if ($text -match "(?m)^#?\s*Errors:\s*[1-9]") {
        throw "Simulator errors were reported in $LogPath"
    }
}

Push-Location -LiteralPath $WorkDir
try {
    Invoke-Checked $vlib @("work")
    Invoke-Checked $vlog @(
        "-sv", "-work", "work",
        (Join-Path $assets "aux_pzt_lock_controller.v"),
        (Join-Path $assets "fv_adc_average.v"),
        (Join-Path $assets "aux_pzt_dac.v"),
        (Join-Path $assets "telemetry_snapshot.v"),
        (Join-Path $assets "tb_aux_pzt_lock.sv"),
        (Join-Path $assets "tb_pi2d.sv"),
        "-l", "compile_latest.log"
    )
    Invoke-Checked $vsim @("-c", "work.tb_pi2d", "-do", "run -all; quit -f", "-l", "tb_pi2d.log")
    Invoke-Checked $vsim @("-c", "work.tb_pi2d_plant", "-do", "run -all; quit -f", "-l", "tb_pi2d_plant.log")
    Require-LogText "tb_pi2d.log" "PI2D AND TELEMETRY TESTS PASSED"
    Require-LogText "tb_pi2d_plant.log" "ALL TESTS PASSED"

    if (-not $SkipLegacy) {
        Invoke-Checked $vlog @(
            "-sv", "-work", "work",
            (Join-Path $assets "pid_error_lock.v"),
            (Join-Path $assets "tb_pid_error_lock.sv"),
            (Join-Path $assets "tb_pid_parameter_edges.sv"),
            "-l", "compile_legacy.log"
        )
        Invoke-Checked $vsim @("-c", "work.tb_pid_error_lock", "-do", "run -all; quit -f", "-l", "tb_pid_error_lock.log")
        Invoke-Checked $vsim @("-c", "work.tb_pid_parameter_edges", "-do", "run -all; quit -f", "-l", "tb_pid_parameter_edges.log")
        Require-LogText "tb_pid_error_lock.log" "PASS: PID arithmetic, cadence, signed extremes, limits and lock hysteresis"
        Require-LogText "tb_pid_parameter_edges.log" "PASS_PID_PARAMETER_EDGES"
    }
} finally {
    Pop-Location
}

Write-Output "FPGA_PI2D_PID_REGRESSION_PASSED"
Write-Output "Logs: $WorkDir"

