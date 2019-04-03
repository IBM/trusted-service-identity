#!/usr/bin/env bash

DIR="$(dirname "$0")"
STATEDIR=${STATEDIR:-/tmp}
mkdir -p ${STATEDIR}

source ${DIR}/startup_tpm.sh

key="$(cat ${STATEDIR}/tpmkeyurl)"
x5c="$(cat ${STATEDIR}/x5c)"

gen-jwt.py "$key" "--x5c" $@
