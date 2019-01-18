#!/usr/bin/env bash

DIR="$(dirname "$0")"
STATEDIR=${STATEDIR:-/tmp}

source ${DIR}/startup_tpm.sh

cd /usr/local/bin || exit
./run-server.sh
