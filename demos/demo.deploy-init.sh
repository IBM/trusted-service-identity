#!/bin/bash

# this script requires https://github.com/duglin/tools/tree/master/demoscript
declare DEMOFILE=~/workspace/tools/demoscript/demoscript
if [ ! -f "$DEMOFILE" ]; then
    echo "$DEMOFILE does not exist."
    exit 1
fi
source ${DEMOFILE}

realpath_cmd="realpath --version"
if [[ ! $(eval ${realpath_cmd}) ]]; then
  echo "realpath installation required to proceed"
  echo "(on mac: brew install coreutils)"
  exit 1
fi

jq_cmd="jq --version"
if [[ ! $(eval ${jq_cmd}) ]]; then
  echo "jq installation required to proceed"
  echo "(https://stedolan.github.io/jq/download/)"
  exit 1
fi

SCRIPT_PATH=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
TSI_VERSION=$(cat ${SCRIPT_PATH}/../tsi-version.txt)
UTILS=$(realpath --relative-to=`pwd` ${SCRIPT_PATH}/../utils)
EXAMPLES=$(realpath --relative-to=`pwd` ${SCRIPT_PATH}/../examples)
TESTFILE="${EXAMPLES}/myubuntu-initC.yaml"
kk="kubectl -n trusted-identity"

## create help menu:
helpme()
{
  cat <<HELPMEHELPME
Make sure ROOT_TOKEN and VAULT_ADDR environment variables are set.
export ROOT_TOKEN=
export VAULT_ADDR=(vault address in format http://vault.domain)

syntax:
   $0
HELPMEHELPME
}

# validate the arguments
if [[ "$ROOT_TOKEN" == "" || "$VAULT_ADDR" == "" ]] ; then
  echo "ROOT_TOKEN and VAULT_ADDR enviroment variables must be set"
  helpme
  exit 1
elif [[ "$1" == "-?" || "$1" == "-h" || "$1" == "--help" ]] ; then
  helpme
  exit 0
fi

# this does not work... :(
#doit "cd ../"
#doit pwd

secrets(){
# Get the secret from the deployment file
doit "cat ${TESTFILE} | grep -B1 -A6 'tsi.secrets:'"
comment "build the secrets script..."
doit --noexec "${EXAMPLES}/vault/demo.secret-maker.sh -f ${TESTFILE} -n test > init.secrets.sh"
${EXAMPLES}/vault/demo.secret-maker.sh -f ${TESTFILE} -n test > init.secrets.sh
doit --neexec "sed 's/secret=xxx/secret=Password4InitTest/g' init.secrets.sh > init.secrets.1.sh"
sed 's/secret=xxx/secret=Password4InitTest/g' job.secrets.sh > init.secrets.1.sh

# load the secrets to Vault
doit vault login $ROOT_TOKEN
doit sh init.secrets.1.sh
}


job_deploy(){
# create the deployment
comment "Create a test deployment with 2 init containers"
doit --ignorerc  "kubectl create ns test"
doit --ignorerc kubectl -n test delete -f ${TESTFILE}
doit kubectl -n test get po
doit kubectl -n test create -f ${TESTFILE}
doit kubectl -n test get po
doit kubectl -n test logs $(kubectl -n test get po | grep myubuntu-init | grep -v "Terminating" | awk '{print $1}' |  sed -n 1p ) -c jwt-init
doit kubectl -n test logs $(kubectl -n test get po | grep myubuntu-init | grep -v "Terminating" | awk '{print $1}' |  sed -n 1p ) --all-containers=true
doit --ignorerc  kubectl -n test get po -w

}

secrets
job_deploy
