#!/bin/bash
# this script requires https://github.com/duglin/tools/tree/master/demoscript
declare DEMOFILE=~/workspace/tools/demoscript/demoscript
if [ ! -f "$DEMOFILE" ]; then
    echo "$DEMOFILE does not exist."
		exit 1
fi
source ${DEMOFILE}

comment Show the secrets in 'myubuntu.yaml'
doit "cat ../myubuntu.yaml | grep -B1 -A6 'tsi.secrets:'"
comment "build the secrets script..."
doit --noexec '../vault/demo.secret-maker.sh -f ../myubuntu.yaml -n test > myubuntu.secrets.sh'
../vault/demo.secret-maker.sh -f ../myubuntu.yaml -n test > myubuntu.secrets.sh
doit --neexec "sed 's/secret=xxx/secret=ThisIs5ecurePa55word/g' myubuntu.secrets.sh > myubuntu.secrets.1.sh"
sed 's/secret=xxx/secret=ThisIs5ecurePa55word/g' myubuntu.secrets.sh > myubuntu.secrets.1.sh

doit vault login $ROOT_TOKEN
doit sh myubuntu.secrets.1.sh
doit vault kv list secret/tsi-ri/eu-de/30beed0665d9cb4df616cca84ef2c06d2323e02869fcca8bbfbf0d8c5a3987cc
doit vault kv get -format=json secret/tsi-ri/eu-de/30beed0665d9cb4df616cca84ef2c06d2323e02869fcca8bbfbf0d8c5a3987cc/mysecret1
doit vault kv list secret/tsi-r/eu-de/
doit vault kv get -format=json secret/tsi-r/eu-de/mysecret2
comment "Create a myubuntu pod"
sleep 10
comment "Let's delete one secret"
doit vault kv delete secret/tsi-r/eu-de/mysecret2
doit vault kv get -format=json secret/tsi-r/eu-de/mysecret2
doit kubectl -n test logs -f $(kubectl -n test get po | grep myubuntu | grep Running | awk '{print $1}') -c jwt-sidecar
