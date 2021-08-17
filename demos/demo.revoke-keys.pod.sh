#!/bin/bash
# this script requires https://github.com/duglin/tools/tree/main/demoscript
declare DEMOFILE=~/workspace/tools/demoscript/demoscript
if [ ! -f "$DEMOFILE" ]; then
    echo "$DEMOFILE does not exist."
    exit 1
fi
source ${DEMOFILE}

EXAMPLES="../examples"

doit --ignorerc kubectl -n test delete -f ${EXAMPLES}/myubuntu.yaml
doit kubectl -n test get po
doit kubectl -n test create -f ${EXAMPLES}/myubuntu.yaml
doit kubectl -n test get po
doit kubectl -n test get po

ttyDoit kubectl -n test exec -it $(kubectl -n test get po | grep myubuntu | grep Running | awk '{print $1}' |  sed -n 1p ) -c myubuntu -- bash 10<<EOF
  cat /tsi-secrets/mysecret1
  watch ls -l /tsi-secrets/
  exit
EOF
