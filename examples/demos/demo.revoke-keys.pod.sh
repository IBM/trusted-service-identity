#!/bin/bash
# this script requires https://github.com/duglin/tools/tree/master/demoscript
declare DEMOFILE=~/workspace/tools/demoscript/demoscript
if [ ! -f "$DEMOFILE" ]; then
    echo "$DEMOFILE does not exist."
		exit 1
fi
source ${DEMOFILE}

doit --ignorerc kubectl -n test delete -f ../myubuntu.yaml
doit kubectl -n test get po
doit kubectl -n test create -f ../myubuntu.yaml
doit kubectl -n test get po
doit kubectl -n test get po
#doit kubectl -n test exec -it $(kubectl -n test get po | grep myubuntu | awk '{print $1}' |  sed -n 1p ) -c myubuntu bash
#doit watch ls -l /tsi-secrets/mysecret/
#exit


ttyDoit kubectl -n test exec -it $(kubectl -n test get po | grep myubuntu | grep Running | awk '{print $1}' |  sed -n 1p ) -c myubuntu bash 10<<EOF
  cat /tsi-secrets/mysecrets/mysecret1
	watch ls -l /tsi-secrets/mysecrets/
	exit
EOF
