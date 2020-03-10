#!/usr/bin/env bash

DIR="$(dirname "$0")"
STATEDIR=${STATEDIR:-/tmp}
mkdir -p ${STATEDIR}

source ${DIR}/startup_tpm.sh

cd /usr/local/bin || exit
./run-jss-server.sh
