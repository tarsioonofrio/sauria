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

# The experiment starts after AXI-Lite configuration is complete, so the
# default view measures accelerator-internal paths. Select "wrapper" explicitly
# to include the external AW/W valid-to-ready handshake paths as well.
set timing_scope "accelerator_internal"
if {[info exists ::env(SAURIA_TIMING_SCOPE)]} {
    set timing_scope $::env(SAURIA_TIMING_SCOPE)
}
switch -- $timing_scope {
    wrapper {
        puts "SAURIA timing scope: complete wrapper, including AXI-Lite handshake"
    }
    accelerator_internal {
        set_false_path \
            -from [get_ports {i_ctrl_aw_valid i_ctrl_w_valid}] \
            -to   [get_ports {o_ctrl_aw_ready o_ctrl_w_ready}]
        puts "SAURIA timing scope: accelerator internal; excluded AXI-Lite AW/W valid-to-ready paths"
    }
    default {
        error "Unsupported SAURIA_TIMING_SCOPE '$timing_scope' (use wrapper or accelerator_internal)"
    }
}
