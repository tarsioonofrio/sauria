##############################################################
## Logical / Physical synthesis constraints for SAURIA ASIC ##
##############################################################

set sdc_version 1.5
set_load_unit -femtofarads
set_time_unit -nanoseconds

# Override the target period for one-off timing points without changing the
# configuration. The normal campaign remains at 500 MHz (2.0 ns).
if {[info exists ::env(SAURIA_CLOCK_PERIOD_NS)]} {
    set period_clock $::env(SAURIA_CLOCK_PERIOD_NS)
} else {
    set period_clock 2.0
}
puts "SAURIA clock constraint: period=${period_clock} ns"
set clock_port [get_ports {i_clk}]
set reset_port [get_ports {i_rstn}]
create_clock -name {clk} -period $period_clock $clock_port
set_false_path -from $reset_port

# Half-cycle external budget, matching the FastConv input-flow convention.
set data_inputs [remove_from_collection [all_inputs] $clock_port]
set data_inputs [remove_from_collection $data_inputs $reset_port]
set_driving_cell -lib_cell GINVD1BWP30P140 $data_inputs
set_load [load_of [get_lib_pins GINVMCOD8BWP30P140/I]] [all_outputs]
set_input_delay -clock clk [expr {$period_clock/2}] $data_inputs
set_output_delay -clock clk [expr {$period_clock/2}] [all_outputs]
