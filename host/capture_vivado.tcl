# Run in Vivado Tcl Console AFTER the matching bitstream was programmed.
# This script never programs hardware and never enables feedback.
# source {C:/path/to/project/host/capture_vivado.tcl}
# To stop: set ::aux_telemetry_stop 1
namespace eval ::aux_telemetry {
 variable root [file dirname [file normalize [info script]]]
 variable ila
 variable logfile
 variable busy 0
}
proc ::aux_telemetry::capture {} {
 variable root;variable ila;variable logfile;variable busy
 if {$::aux_telemetry_stop} {puts "Telemetry stopped";return}
 if {$busy} {return}
 set busy 1
 set temporary [file join $root live capture_tmp.csv]
 set latest [file join $root live latest.csv]
 if {[catch {
  run_hw_ila -trigger_now $ila
  wait_on_hw_ila -timeout 0.083333 $ila
  set captured [upload_hw_ila_data $ila]
  write_hw_ila_data -force -csv_file $temporary $captured
  file rename -force $temporary $latest
  puts $logfile "[clock format [clock seconds] -format {%Y-%m-%dT%H:%M:%S}] CAPTURE_OK"
 } message]} {
  puts "Telemetry capture error: $message"
  puts $logfile "CAPTURE_ERROR $message"
 }
 flush $logfile
 set busy 0
 if {!$::aux_telemetry_stop} {after 2000 ::aux_telemetry::capture}
}
load_features labtools
set ::aux_telemetry::devices {}
# A Zynq target can also expose an ARM DAP TAP. Select the FPGA part only.
foreach device [get_hw_devices -quiet] {
 if {[string match "*7z020*" [string tolower [get_property PART $device]]]} {lappend ::aux_telemetry::devices $device}
}
if {[llength $::aux_telemetry::devices] != 1} {error "Connect one xc7z020 FPGA in Hardware Manager first (ARM DAP is ignored)."}
set ::aux_telemetry::device [lindex $::aux_telemetry::devices 0]
set ::aux_telemetry::ltx [file normalize [file join $::aux_telemetry::root .. bitstream aux_pzt_pi2d_lock.ltx]]
if {![file exists $::aux_telemetry::ltx]} {error "Matching LTX not found"}
set_property PROBES.FILE $::aux_telemetry::ltx $::aux_telemetry::device
refresh_hw_device $::aux_telemetry::device
set ::aux_telemetry::matches [get_hw_ilas -of_objects $::aux_telemetry::device -filter {CELL_NAME =~ "*u_ila*"}]
if {[llength $::aux_telemetry::matches] != 1} {error "Expected the current project's u_ila; program its matching bitstream first."}
set ::aux_telemetry::ila [lindex $::aux_telemetry::matches 0]
set_property CONTROL.TRIGGER_POSITION 0 $::aux_telemetry::ila
file mkdir [file join $::aux_telemetry::root live]
set ::aux_telemetry::logfile [open [file join $::aux_telemetry::root live capture.log] a]
set ::aux_telemetry_stop 0
::aux_telemetry::capture
