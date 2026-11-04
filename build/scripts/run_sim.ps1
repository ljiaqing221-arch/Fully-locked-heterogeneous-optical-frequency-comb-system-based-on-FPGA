param([string]$VivadoBin='D:\Workapps\Vivado2025.2\2025.2\Vivado\bin')
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$taskSim=Join-Path $taskRoot 'build/sim_build'
[void](New-Item -ItemType Directory -Path $taskSim -Force)
[void](New-Item -ItemType Directory -Path (Join-Path $taskRoot 'build/reports') -Force)
Push-Location $taskSim
try {
 & (Join-Path $VivadoBin 'xvlog.bat') --sv ../../src/rtl/fv_adc_average.v ../../src/rtl/aux_pzt_lock_controller.v ../../src/rtl/aux_pzt_dac.v ../../sim/tb_aux_pzt_lock.sv
 if($LASTEXITCODE -ne 0){throw 'xvlog failed'}
 & (Join-Path $VivadoBin 'xelab.bat') tb_aux_pzt_lock -s aux_pzt_sim
 if($LASTEXITCODE -ne 0){throw 'xelab failed'}
 & (Join-Path $VivadoBin 'xsim.bat') aux_pzt_sim -runall -log ../reports/simulation.log
 if($LASTEXITCODE -ne 0){throw 'xsim failed'}
 & (Join-Path $VivadoBin 'xvlog.bat') --sv ../../src/rtl/fixed_lo_clock.v ../../sim/tb_fixed_lo.sv
 if($LASTEXITCODE -ne 0){throw 'LO xvlog failed'}
 & (Join-Path $VivadoBin 'xvlog.bat') (Join-Path (Split-Path -Parent $VivadoBin) 'data/verilog/src/glbl.v')
 if($LASTEXITCODE -ne 0){throw 'glbl compile failed'}
 & (Join-Path $VivadoBin 'xelab.bat') tb_fixed_lo glbl -L unisims_ver -s lo_sim
 if($LASTEXITCODE -ne 0){throw 'LO xelab failed'}
 & (Join-Path $VivadoBin 'xsim.bat') lo_sim -runall -log ../reports/lo_simulation.log
 if($LASTEXITCODE -ne 0){throw 'LO xsim failed'}
 if(-not(Select-String -LiteralPath ../reports/lo_simulation.log -Pattern 'LO TESTS PASSED' -Quiet)){throw 'No LO PASS marker'}
 if(-not(Select-String -LiteralPath ../reports/simulation.log -Pattern 'ALL TESTS PASSED' -Quiet)){throw 'No simulation PASS marker'}
 & (Join-Path $VivadoBin 'xvlog.bat') --sv ../../src/rtl/telemetry_snapshot.v ../../sim/tb_pi2d.sv
 if($LASTEXITCODE -ne 0){throw 'PI2D xvlog failed'}
 & (Join-Path $VivadoBin 'xelab.bat') tb_pi2d -s pi2d_sim
 if($LASTEXITCODE -ne 0){throw 'PI2D xelab failed'}
 & (Join-Path $VivadoBin 'xsim.bat') pi2d_sim -runall -log ../reports/pi2d_simulation.log
 if($LASTEXITCODE -ne 0){throw 'PI2D xsim failed'}
 if(-not(Select-String -LiteralPath ../reports/pi2d_simulation.log -Pattern 'PI2D AND TELEMETRY TESTS PASSED' -Quiet)){throw 'No PI2D PASS marker'}
 & (Join-Path $VivadoBin 'xelab.bat') tb_pi2d_plant -s pi2d_plant_sim
 if($LASTEXITCODE -ne 0){throw 'PI2D plant xelab failed'}
 & (Join-Path $VivadoBin 'xsim.bat') pi2d_plant_sim -runall -log ../reports/pi2d_plant_simulation.log
 if($LASTEXITCODE -ne 0){throw 'PI2D plant xsim failed'}
 if(-not(Select-String -LiteralPath ../reports/pi2d_plant_simulation.log -Pattern 'ALL TESTS PASSED' -Quiet)){throw 'No PI2D plant PASS marker'}
} finally {Pop-Location}
