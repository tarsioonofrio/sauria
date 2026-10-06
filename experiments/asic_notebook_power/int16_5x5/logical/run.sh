#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR"

source /usr/share/Modules/init/bash
module purge
module use /soft64/modulefiles
module load cadence/genus/211
genus -f logical_synthesis.tcl
