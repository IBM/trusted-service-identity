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
--set ti-key-release-1.runSidecar=true \
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
doit "cat ${EXAMPLES}/myubuntu.yaml | grep -B1 -A6 'tsi.secrets:'"
comment "build the secrets script..."
doit --noexec "${EXAMPLES}/vault/demo.secret-maker.sh -f ${EXAMPLES}/myubuntu.yaml -n test > myubuntu.secrets.sh"
${EXAMPLES}/vault/demo.secret-maker.sh -f ${EXAMPLES}/myubuntu.yaml -n test > myubuntu.secrets.sh
doit --neexec "sed 's/secret=xxx/secret=ThisIs5ecurePa55word/g' myubuntu.secrets.sh > myubuntu.secrets.1.sh"
sed 's/secret=xxx/secret=ThisIs5ecurePa55word/g' myubuntu.secrets.sh > myubuntu.secrets.1.sh

# load the secrets to Vault
doit vault login $ROOT_TOKEN
doit sh myubuntu.secrets.1.sh
doit vault kv list secret/tsi-ri/eu-de/30beed0665d9cb4df616cca84ef2c06d2323e02869fcca8bbfbf0d8c5a3987cc
doit vault kv get -format=json secret/tsi-ri/eu-de/30beed0665d9cb4df616cca84ef2c06d2323e02869fcca8bbfbf0d8c5a3987cc/mysecret1
doit vault kv list secret/tsi-r/eu-de/
doit vault kv get -format=json secret/tsi-r/eu-de/mysecret2
}


pod_deploy(){
# create the deployment
comment "Create a myubuntu pod"
doit --ignorerc  "kubectl create ns test"
doit --ignorerc kubectl -n test delete -f ${EXAMPLES}/myubuntu.yaml
doit kubectl -n test get po
doit kubectl -n test create -f ${EXAMPLES}/myubuntu.yaml
doit kubectl -n test get po
doit kubectl -n test get po

ttyDoit kubectl -n test exec -it $(kubectl -n test get po | grep myubuntu | grep Running | awk '{print $1}' |  sed -n 1p ) -c myubuntu bash 10<<EOF
  cat /tsi-secrets/mysecret1
  exit
EOF

sleep 10
comment "Let's delete one secret"
doit vault kv delete secret/tsi-r/eu-de/mysecret2
doit vault kv get -format=json secret/tsi-r/eu-de/mysecret2
doit kubectl -n test logs -f $(kubectl -n test get po | grep myubuntu | grep Running | awk '{print $1}') -c jwt-sidecar
}

cleanup
tsi_helm
secrets
pod_deploy
