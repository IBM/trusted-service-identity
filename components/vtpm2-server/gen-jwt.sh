#!/usr/bin/env bash

DIR="$(dirname "$0")"
STATEDIR=${STATEDIR:-/tmp}

source ${DIR}/startup_tpm.sh

key="$(cat /tmp/tpmkeyurl)"

gen-jwt.py "$key" $@
