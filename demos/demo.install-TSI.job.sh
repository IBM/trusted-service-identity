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
TESTFILE="${EXAMPLES}/sample-job.yaml"
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

cleanup() {
comment "This demo install TSI with sidecar disabled (Job example)"
comment "This demo script works only with IKS cluster"
comment "Using VAULT_ADDR=$VAULT_ADDR"
comment "Get the cluster info"
doit --noexec "$UTILS/get-cluster-info.sh > cluster-info.txt"
CL_INFO=$("$UTILS/get-cluster-info.sh")
echo $CL_INFO > cluster-info.txt
doit --noexec "source cluster-info.txt"
source cluster-info.txt
rm cluster-info.txt
doit "echo REGION=$REGION; echo CLUSTER_NAME=$CLUSTER_NAME"

comment "Clean-up all"
doit --ignorerc "$UTILS/cleanup.sh"
doit --ignorerc "$UTILS/init-namespace.sh"
}

tsi_helm(){
doit "helm install ../charts/tsi-node-setup-${TSI_VERSION}.tgz --debug --name tsi-setup --set reset.all=true \
--set cluster.name=$CLUSTER_NAME --set cluster.region=$REGION"
doit "$kk get po"

doit "helm install ../charts/ti-key-release-2-${TSI_VERSION}.tgz --debug --name tsi \
--set ti-key-release-1.cluster.name=$CLUSTER_NAME \
--set ti-key-release-1.cluster.region=$REGION \
--set ti-key-release-1.vaultAddress=$VAULT_ADDR \
--set ti-key-release-1.runSidecar=false \
--set jssService.type=jss-server"
doit "$kk get po"

comment "Register this cluster with Vault"
doit "../examples/vault/demo.register-JSS.sh "

comment "Remove the TSI setup deployment..."
doit "helm ls"
doit "helm delete --purge tsi-setup"
doit "$kk get po"
}

secrets(){
# Get the secret from the deployment file
doit "cat ${TESTFILE} | grep -B1 -A6 'tsi.secrets:'"
comment "build the secrets script..."
doit --noexec "${EXAMPLES}/vault/demo.secret-maker.sh -f ${TESTFILE} -n test > job.secrets.sh"
${EXAMPLES}/vault/demo.secret-maker.sh -f ${TESTFILE} -n test > job.secrets.sh
doit --neexec "sed 's/secret=xxx/secret=Password4JobTest/g' job.secrets.sh > job.secrets.1.sh"
sed 's/secret=xxx/secret=Password4JobTest/g' job.secrets.sh > job.secrets.1.sh

# load the secrets to Vault
doit vault login $ROOT_TOKEN
doit sh job.secrets.1.sh
}


job_deploy(){
# create the deployment
comment "Create a test job"
doit --ignorerc  "kubectl create ns test"
doit --ignorerc kubectl -n test delete -f ${TESTFILE}
doit kubectl -n test get po
doit kubectl -n test create -f ${TESTFILE}
doit kubectl -n test get jobs
doit kubectl -n test logs $(kubectl -n test get po | grep myjob | awk '{print $1}' |  sed -n 1p ) -c jwt-init
doit kubectl -n test logs $(kubectl -n test get po | grep myjob | awk '{print $1}' |  sed -n 1p ) --all-containers=true
doit kubectl -n test get po -w

# doit --noexec "kubectl -n test logs $(kubectl -n test get po | grep myjob | grep Running | awk '{print $1}' |  sed -n 1p ) -c myjob"
doit kubectl -n test logs $(kubectl -n test get po | grep myjob | awk '{print $1}' |  sed -n 1p ) -c myjob
doit kubectl -n test get jobs
doit kubectl -n test get po
}
#
#cleanup
#tsi_helm
#secrets
job_deploy
