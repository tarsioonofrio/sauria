#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
RTL_DIR=${RTL_DIR:-$REPO_ROOT/RTL}
PULP_DIR=${PULP_DIR:-$REPO_ROOT/pulp_platform}
export RTL_DIR PULP_DIR

VERSION=${1:-}

if [ -z "$VERSION" ]
then
      echo "No version passed. Assuming 'FP16_8x16'. Please use the script as:"
      echo "source compile_sauria.sh VERSION"
      VERSION="FP16_8x16"
fi

make clean
make version="$VERSION"
