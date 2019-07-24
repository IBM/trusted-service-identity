#!/usr/bin/env bash

DIR="$(dirname "$0")"
STATEDIR=${STATEDIR:-/host/tsi-secure}
#mkdir -p ${STATEDIR}

#source ${DIR}/init-jss.sh

cd /usr/local/bin || exit
./run-web-server.sh
