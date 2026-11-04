if {[info exists ::env(AUX_PZT_BUILD_ROOT)]} {set root $::env(AUX_PZT_BUILD_ROOT)} else {set root [file dirname [file dirname [file dirname [file normalize [info script]]]]]}
open_project [file join $root vivado_project aux_pzt_pi2d_lock.xpr]
puts "Assigned adjacent package balls U20/V20; verify board header routing, bank33 VCCO and external LO buffer before programming."
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis failed"}
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation failed"}
open_run impl_1
report_timing_summary -file [file join $root build reports timing_implementation.txt]
report_drc -file [file join $root build reports drc_implementation.txt]
report_bus_skew -file [file join $root build reports bus_skew_implementation.txt]
report_utilization -file [file join $root build reports utilization_implementation.txt]
file mkdir [file join $root bitstream]
write_debug_probes -force [file join $root bitstream aux_pzt_pi2d_lock.ltx]
file copy -force [file join [get_property DIRECTORY [get_runs impl_1]] top_aux_pzt_lock.bit] [file join $root bitstream aux_pzt_pi2d_lock.bit]
puts "Review timing and board voltage ranges before programming; VIO loop defaults DISABLED."
close_project
