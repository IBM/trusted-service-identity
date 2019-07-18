#!/usr/bin/env bash

DIR="$(dirname "$0")"
STATEDIR=${STATEDIR:-/tmp}
mkdir -p ${STATEDIR}

key="$(cat ${STATEDIR}/tpmkeyurl)"

gen-jwt.py "$key" $@
