#!/usr/bin/env bash
set -euo pipefail

POWER_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source /usr/share/Modules/init/bash
module purge
module use /soft64/modulefiles
module load cadence/genus/211
genus -f "$POWER_ROOT/power.tcl"
