###############################################################################
# Shared Genus body for a project-local configuration.
###############################################################################

puts "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
puts "Load the pdk using MMMC"
puts "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
read_mmmc [file join $CONFIG_ROOT scripts mmmc_tsmc_28_bv.tcl]

puts "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
puts "Configuration of the Genus"
puts "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
set_multi_cpu_usage -local_cpu 112
set_db lp_default_probability 0.5
set_db syn_global_effort high
set_db auto_ungroup none
set_db hdl_parameter_naming_style ""
set_db interconnect_mode ple
set_db hdl_error_on_latch true

puts "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
puts "Control Clock Gating"
puts "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
set_db lp_insert_clock_gating true

puts "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
puts "Load hdl files"
puts "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
if {[llength $DEFINE_FLAGS] > 0} {
    set DEFINE_STRING [join $DEFINE_FLAGS " "]
    read_hdl -define $DEFINE_STRING -sv {*}$HDL_FILES
} else {
    read_hdl -sv {*}$HDL_FILES
}


puts "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
puts "Elaboration"
puts "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
if {[llength $TOP_PARAMETERS] > 0} {
    elaborate ${TOP_MODULE} -parameters ${TOP_PARAMETERS}
} else {
    elaborate ${TOP_MODULE}
}
init_design

if {[info exists DEBUG_PRESERVE_CONV_DATAPATH] && $DEBUG_PRESERVE_CONV_DATAPATH} {
    puts "Debug: preserve Conv datapath observability"
    set_db delete_unloaded_insts false
    set_db optimize_constant_0_flops false
}

puts "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
puts "Synthesis - mapping and optimization"
puts "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
syn_generic
syn_map
syn_opt

puts "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
puts "Write Reports"
puts "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
file mkdir [file join $OUT_FILES reports]
file mkdir [file join $OUT_FILES gate_level]
file mkdir [file join $OUT_FILES physical_synthesis work]

report_clock_gating > [file join $OUT_FILES reports ${TOP_MODULE}_clock_gating.rpt]
report_ple > [file join $OUT_FILES reports ${TOP_MODULE}_ple.rpt]
report_gates > [file join $OUT_FILES reports ${TOP_MODULE}_gates.rpt]
report_area > [file join $OUT_FILES reports ${TOP_MODULE}_area.rpt]

set CURRENT_VIEW analysis_view_0p81v_125c_capwst_slowest
set_analysis_view -setup ${CURRENT_VIEW} -hold ${CURRENT_VIEW}
report_timing > [file join $OUT_FILES reports ${TOP_MODULE}_timing_setup_${CURRENT_VIEW}.rpt]
report_power -unit mW > [file join $OUT_FILES reports ${TOP_MODULE}_power_${CURRENT_VIEW}.rpt]

set CURRENT_VIEW analysis_view_0p90v_25c_captyp_nominal
set_analysis_view -setup ${CURRENT_VIEW} -hold ${CURRENT_VIEW}
report_timing > [file join $OUT_FILES reports ${TOP_MODULE}_timing_setup_${CURRENT_VIEW}.rpt]
report_power -unit mW > [file join $OUT_FILES reports ${TOP_MODULE}_power_${CURRENT_VIEW}.rpt]

set CURRENT_VIEW analysis_view_0p99v_m40c_capbst_fastest
set_analysis_view -setup ${CURRENT_VIEW} -hold ${CURRENT_VIEW}
report_timing > [file join $OUT_FILES reports ${TOP_MODULE}_timing_setup_${CURRENT_VIEW}.rpt]
report_power -unit mW > [file join $OUT_FILES reports ${TOP_MODULE}_power_${CURRENT_VIEW}.rpt]
report_timing -lint -verbose > [file join $OUT_FILES reports ${TOP_MODULE}_timing_setup_${CURRENT_VIEW}_verbose.rpt]
report_timing -unconstrained > [file join $OUT_FILES reports ${TOP_MODULE}_timing_setup_${CURRENT_VIEW}_verbose_unconstrained.rpt]

puts "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
puts "Write netlist"
puts "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
write_hdl > [file join $OUT_FILES gate_level ${TOP_MODULE}_logic_mapped.v]

set CURRENT_VIEW analysis_view_0p81v_125c_capwst_slowest
set_analysis_view -setup ${CURRENT_VIEW} -hold ${CURRENT_VIEW}
write_sdf > [file join $OUT_FILES gate_level ${TOP_MODULE}_${CURRENT_VIEW}.sdf]

set CURRENT_VIEW analysis_view_0p90v_25c_captyp_nominal
set_analysis_view -setup ${CURRENT_VIEW} -hold ${CURRENT_VIEW}
write_sdf > [file join $OUT_FILES gate_level ${TOP_MODULE}_${CURRENT_VIEW}.sdf]

set CURRENT_VIEW analysis_view_0p99v_m40c_capbst_fastest
set_analysis_view -setup ${CURRENT_VIEW} -hold ${CURRENT_VIEW}
write_sdf > [file join $OUT_FILES gate_level ${TOP_MODULE}_${CURRENT_VIEW}.sdf]

set_analysis_view -setup analysis_view_0p81v_125c_capwst_slowest \
                  -hold analysis_view_0p99v_m40c_capbst_fastest
write_design -innovus -base_name [file join $OUT_FILES physical_synthesis work data]

set CURRENT_VIEW analysis_view_0p90v_25c_captyp_nominal
set_analysis_view -setup ${CURRENT_VIEW} -hold ${CURRENT_VIEW}
write_db [file join $OUT_FILES gate_level ${TOP_MODULE}_logic_mapped.db]

exit
