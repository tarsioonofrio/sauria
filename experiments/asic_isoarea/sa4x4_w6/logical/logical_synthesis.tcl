###############################################################################
# Project-local logical synthesis flow.
#
# This file is intentionally self-contained. A synthesis configuration uses
# list-file.txt, list-define.txt, list-incdir.txt, top-module.txt, and the
# optional top-parameters.txt at CONFIG_ROOT.
###############################################################################

# Resolve paths from the configuration, not from the process working directory.
set LOGICAL_ROOT [file normalize [file dirname [info script]]]
set CONFIG_ROOT [file normalize [file join $LOGICAL_ROOT ..]]
set GIT_ROOT [exec git -C $CONFIG_ROOT rev-parse --show-toplevel]
set OUT_FILES [file normalize [file join $LOGICAL_ROOT results]]

# The top is configurable per synthesis directory. Keep System as the default
# so an empty template remains useful for the system wrapper.
set TOP_MODULE system
set top_file [file join $CONFIG_ROOT top-module.txt]
if {[file exists $top_file]} {
    set fp_top [open $top_file r]
    while {[gets $fp_top line] >= 0} {
        set line_trim [string trim $line]
        if {$line_trim ne "" && ![string match "#*" $line_trim]} {
            set TOP_MODULE $line_trim
            break
        }
    }
    close $fp_top
}

# Optional parameter overrides use one NAME=VALUE per line. They are useful
# for parameterized streaming cores such as NUM_MULT=2 without changing RTL.
set TOP_PARAMETERS [list]
set parameters_file [file join $CONFIG_ROOT top-parameters.txt]
if {[file exists $parameters_file]} {
    set fp_parameters [open $parameters_file r]
    while {[gets $fp_parameters line] >= 0} {
        set line_trim [string trim $line]
        if {$line_trim ne "" && ![string match "#*" $line_trim]} {
            lappend TOP_PARAMETERS $line_trim
        }
    }
    close $fp_parameters
}

# Resolve a list entry as an absolute path, accepting both repository-relative
# paths (the normal form) and paths relative to the configuration directory.
proc resolve_project_file {entry config_root git_root} {
    if {[file pathtype $entry] eq "absolute"} {
        return [file normalize $entry]
    }
    set from_config [file normalize [file join $config_root $entry]]
    if {[file exists $from_config]} {
        return $from_config
    }
    return [file normalize [file join $git_root $entry]]
}

# Read list-file.txt into a Tcl list so paths containing spaces are preserved.
set file_list_path [file join $CONFIG_ROOT list-file.txt]
set HDL_FILES [list]
if {[file exists $file_list_path]} {
    set fp [open $file_list_path r]
    while {[gets $fp line] >= 0} {
        set line_trim [string trim $line]
        if {$line_trim eq "" || [string match "#*" $line_trim]} {
            continue
        }
        lappend HDL_FILES [resolve_project_file $line_trim $CONFIG_ROOT $GIT_ROOT]
    }
    close $fp
}

# Parse either "NAME=VALUE" or the legacy "-define NAME=VALUE" spelling.
set defines_file [file join $CONFIG_ROOT list-define.txt]
set DEFINE_FLAGS [list]
if {[file exists $defines_file]} {
    set fp_def [open $defines_file r]
    while {[gets $fp_def line] >= 0} {
        set line_trim [string trim $line]
        if {$line_trim eq "" || [string match "#*" $line_trim]} {
            continue
        }
        if {[string match "-define *" $line_trim]} {
            set line_trim [string trim [string range $line_trim 8 end]]
        }
        if {$line_trim ne ""} {
            lappend DEFINE_FLAGS $line_trim
        }
    }
    close $fp_def
}

# Read optional SystemVerilog include directories. SAURIA depends on headers
# from its vendored AXI and common-cells sources; keep them project-local.
set HDL_INC_DIRS [list]
set include_dirs_path [file join $CONFIG_ROOT list-incdir.txt]
if {[file exists $include_dirs_path]} {
    set fp_incdirs [open $include_dirs_path r]
    while {[gets $fp_incdirs line] >= 0} {
        set line_trim [string trim $line]
        if {$line_trim eq "" || [string match "#*" $line_trim]} {
            continue
        }
        lappend HDL_INC_DIRS [resolve_project_file $line_trim $CONFIG_ROOT $GIT_ROOT]
    }
    close $fp_incdirs
}

source [file join $CONFIG_ROOT scripts logical_synthesis_body.tcl]
