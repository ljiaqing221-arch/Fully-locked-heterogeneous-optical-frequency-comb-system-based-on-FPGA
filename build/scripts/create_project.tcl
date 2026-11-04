if {[info exists ::env(AUX_PZT_BUILD_ROOT)]} {set root $::env(AUX_PZT_BUILD_ROOT)} else {set root [file dirname [file dirname [file dirname [file normalize [info script]]]]]}
# Use installed support package directly if a stale user TclStore hides it.
# This only adjusts this process's package search; it does not change Vivado settings.
if {[info exists ::env(XILINX_VIVADO)]} {
 set support [file join $::env(XILINX_VIVADO) data XilinxTclStore support appinit appinit.tcl]
 if {[file exists $support] && [catch {package require ::tclapp::support::appinit 1.2}]} {source $support}
}
set cfg [open [file join $root src rtl aux_pzt_config.vh] r]
set cfgtext [read $cfg];close $cfg
if {![regexp {`define LO_DIVIDE[ \t]+([0-9]+)} $cfgtext -> lodiv]} {error "LO_DIVIDE missing"}
if {![regexp {`define TARGET_FV_CODE[ \t]+16'h([0-9a-fA-F]+)} $cfgtext -> target_init]} {error "TARGET_FV_CODE missing"}
if {![regexp {`define PZT_INIT_CODE[ \t]+16'h([0-9a-fA-F]+)} $cfgtext -> pzt_init]} {error "PZT_INIT_CODE missing"}
if {!($lodiv==1 || ($lodiv>=2 && $lodiv%2==0))} {error "LO_DIVIDE must be 1 or an even integer >=2"}
set build [file join $root vivado_project]
create_project aux_pzt_pi2d_lock $build -part xc7z020clg484-2 -force
set_property target_language Verilog [current_project]
add_files [glob [file join $root src rtl *.v]]
set_property include_dirs [list [file join $root src rtl]] [get_filesets sources_1]
add_files -fileset constrs_1 [file join $root src constraints aux_pzt_lock.xdc]
set lofile [file join $root src constraints lo_frequency.xdc]
set lf [open $lofile w]
puts $lf "create_generated_clock -name mixer_lo_clock -source \[get_ports sys_clk\] -divide_by $lodiv \[get_ports mixer_lo_out\]"
puts $lf "create_generated_clock -name mixer_lo_monitor_clock -source \[get_ports sys_clk\] -divide_by $lodiv \[get_ports mixer_lo_monitor\]"
foreach {envname port} {MIXER_LO_PIN mixer_lo_out MIXER_LO_MONITOR_PIN mixer_lo_monitor} {
 if {[info exists ::env($envname)] && $::env($envname) ne ""} {
  if {![regexp {^[A-Z]+[0-9]+$} $::env($envname)]} {error "Invalid package-pin syntax"}
  puts $lf "set_property PACKAGE_PIN $::env($envname) \[get_ports $port\]"
 }
}
close $lf
add_files -fileset constrs_1 $lofile
set_property top top_aux_pzt_lock [get_filesets sources_1]
create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name clk_wiz_1
# The top-level sys_clk already owns the primary clock/IBUF/BUFG.
# Treat the clock wizard as an internal source to avoid redefining a primary
# clock on its hierarchical clk_in1 pin.
set_property -dict [list CONFIG.PRIM_SOURCE {No_buffer} CONFIG.PRIM_IN_FREQ {50.000} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {50.000} CONFIG.CLK_OUT1_PORT {clk_50M} CONFIG.RESET_TYPE {ACTIVE_HIGH}] [get_ips clk_wiz_1]
create_ip -name vio -vendor xilinx.com -library ip -module_name vio_aux_controls
set_property -dict [list CONFIG.C_NUM_PROBE_IN {0} CONFIG.C_NUM_PROBE_OUT {11} CONFIG.C_PROBE_OUT4_WIDTH {16} CONFIG.C_PROBE_OUT5_WIDTH {16} CONFIG.C_PROBE_OUT4_INIT_VAL 0x$target_init CONFIG.C_PROBE_OUT5_INIT_VAL 0x$pzt_init] [get_ips vio_aux_controls]
create_ip -name ila -vendor xilinx.com -library ip -module_name ila_aux_debug
set props [list CONFIG.C_NUM_OF_PROBES {19} CONFIG.C_DATA_DEPTH {1024}]
set widths {16 16 18 16 3 1 3 1 1 1 1 1 64 64 64 16 32 64 8}
for {set i 0} {$i<19} {incr i} {lappend props CONFIG.C_PROBE${i}_WIDTH [lindex $widths $i]}
set_property -dict $props [get_ips ila_aux_debug]
file mkdir [file join $root build reports]
generate_target all [get_ips]
add_files -fileset sim_1 [glob [file join $root sim *.sv]]
set_property top tb_aux_pzt_lock [get_filesets sim_1]
update_compile_order -fileset sources_1
puts "PROJECT_READY: [file join $build aux_pzt_pi2d_lock.xpr]"
if {[lsearch -exact $argv -synth]>=0 || [lsearch -exact $argv -implement]>=0} {
 launch_runs synth_1 -jobs 2
 wait_on_run synth_1
 if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis run did not finish"}
 open_run synth_1
 report_io -file [file join $root build reports io_synthesis.txt]
 report_clocks -file [file join $root build reports clocks_synthesis.txt]
 report_utilization -file [file join $root build reports utilization.txt]
 report_timing_summary -file [file join $root build reports timing_synthesis.txt]
 write_checkpoint -force [file join $root build reports aux_pzt_lock_synth.dcp]
 puts "SYNTHESIS_PASSED"
}
if {[lsearch -exact $argv -implement]>=0} {
 launch_runs impl_1 -to_step write_bitstream -jobs 2
 wait_on_run impl_1
 if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation failed"}
 open_run impl_1
 report_utilization -file [file join $root build reports utilization_implementation.txt]
 report_timing_summary -file [file join $root build reports timing_implementation.txt]
 report_bus_skew -file [file join $root build reports bus_skew_implementation.txt]
 report_drc -file [file join $root build reports drc_implementation.txt]
 report_methodology -file [file join $root build reports methodology_implementation.txt]
 report_io -file [file join $root build reports io_implementation.txt]
 file mkdir [file join $root bitstream]
 write_debug_probes -force [file join $root bitstream aux_pzt_pi2d_lock.ltx]
 file copy -force [get_property DIRECTORY [get_runs impl_1]]/top_aux_pzt_lock.bit [file join $root bitstream aux_pzt_pi2d_lock.bit]
 puts "IMPLEMENTATION_PASSED"
}
close_project

