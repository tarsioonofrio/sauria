###############################################################################
# Activity-based Genus/Joules power flow for one notebook hardware workload.
###############################################################################
set POWER_ROOT [file normalize [file dirname [info script]]]
set CONFIG_ROOT [file normalize [file join $POWER_ROOT ..]]
set CASE $::env(POWER_CASE)
set RUN_ID $::env(POWER_RUN_ID)
set SIM_CASE [file join $CONFIG_ROOT sim run_artifacts $RUN_ID $CASE]
if {[info exists ::env(LOGICAL_RESULTS_ROOT)]} {
    set RESULTS_ROOT [file normalize $::env(LOGICAL_RESULTS_ROOT)]
} else {
    set RESULTS_ROOT [file join $CONFIG_ROOT logical results]
}
set DB_FILE [file join $RESULTS_ROOT gate_level sauria_asic_top_logic_mapped.db]
set SHM [file join $SIM_CASE gate dut.shm]
set WINDOW_FILE [file join $SIM_CASE gate-layer-window.txt]
if {![file exists $DB_FILE]} { error "Missing Genus database: $DB_FILE" }
if {![file exists $SHM]} { error "Missing Xcelium activity database: $SHM" }
if {![file exists $WINDOW_FILE]} { error "Missing layer window: $WINDOW_FILE" }
set fp [open $WINDOW_FILE r]
if {[gets $fp start_ns] < 0} { close $fp; error "Empty layer window file" }
if {[gets $fp end_ns] < 0} { close $fp; error "Layer window is missing its end time" }
close $fp
if {![string is double -strict $start_ns] || ![string is double -strict $end_ns] || $end_ns <= $start_ns} {
    error "Invalid layer window: start=$start_ns ns end=$end_ns ns"
}
set START_TIME "${start_ns}ns"
set END_TIME "${end_ns}ns"
set LIB_PATH /pdk/tsmc/PDK28/PDK_TSMC28_bv/tcbn28hpcplusbwp30p140_190a/TSMCHOME/digital/Front_End
set TECH_PATH /pdk/tsmc/PDK28/PDK_TSMC28_bv/tcbn28hpcplusbwp30p140_190a/TSMCHOME/digital/Back_End
create_library_set -name libset_0p90v_25c \
    -timing "${LIB_PATH}/timing_power_noise/NLDM/tcbn28hpcplusbwp30p140_180a/tcbn28hpcplusbwp30p140tt0p9v25c.lib"
create_opcond -name opcond_0p90v_25c -voltage 0.90 -temperature 25.0
create_timing_condition -name timing_cond_0p90v_25c -opcond opcond_0p90v_25c -library_sets { libset_0p90v_25c }
create_rc_corner -name rc_corner_25c_captyp -temperature 25.0 \
    -qrc_tech "${TECH_PATH}/qrc/RC_QRC_crn28hpc+_1p09m+ut-alrdl_5x1y1z1u_typical/qrcTechFile"
create_delay_corner -name delay_corner_0p90v_25c_captyp -timing_condition timing_cond_0p90v_25c -rc_corner rc_corner_25c_captyp
create_constraint_mode -name constraints_default -sdc_files [file join $CONFIG_ROOT scripts constraints.sdc]
create_analysis_view -name analysis_view_0p90v_25c_captyp_nominal -constraint_mode constraints_default -delay_corner delay_corner_0p90v_25c_captyp
set_analysis_view -setup analysis_view_0p90v_25c_captyp_nominal -hold analysis_view_0p90v_25c_captyp_nominal
read_db $DB_FILE
set_db interconnect_mode ple
read_stimulus $SHM -dut_instance tb.dut -start $START_TIME -end $END_TIME
puts "POWER_WINDOW_START_NS=$start_ns"
puts "POWER_WINDOW_END_NS=$end_ns"
set OUT [file join $POWER_ROOT results $RUN_ID $CASE power_evaluation.txt]
report_power -header -unit mW > $OUT
puts "POWER_CASE=$CASE"
puts "POWER_REPORT=$OUT"
exit
