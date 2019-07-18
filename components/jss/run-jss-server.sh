#!/usr/bin/env bash

DIR="$(dirname "$0")"
STATEDIR=${STATEDIR:-/tmp}
mkdir -p ${STATEDIR}

source ${DIR}/init-jss.sh

cd /usr/local/bin || exit
./run-web-server.sh
