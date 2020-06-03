#!/bin/bash

# NS - a TSI namespace (where the tsi-setup daemonset is deployed)
TSINS="trusted-identity"

## create help menu:
helpme()
{
  cat <<HELPMEHELPME
This script builds a template for injecting secrets to Vault
It requires installation of 'jq', 'yq' and shell script support

syntax:
   $0 -f [deployment-file-name] -n [namespace]
where:
      [deployment-file-name] - name of the file to inspect
      [namespace] - name of the namespace

HELPMEHELPME
}

# validate the input arguments
if [[ "$1" == "-?" || "$1" == "-h" || "$1" == "--help" || "$2" == "" ]] ; then
    helpme
    exit 1
fi

# check prereqs
jq_cmd="jq --version"
yq_cmd="yq --version"

if [[ ! $(eval ${jq_cmd}) ]]; then
  echo "jq installation required to proceed"
  echo "(https://stedolan.github.io/jq/download/)"
  exit 1
fi

if [[ ! $(eval ${yq_cmd}) ]]; then
  echo "yq installation required to proceed"
  echo "(https://mikefarah.gitbook.io/yq/)"
  exit 1
fi

NS="default"

POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -f|--file)
    FILE="$2"
    shift # past argument
    shift # past value
    ;;
    -n|--namespace)
    NS="$2"
    shift # past argument
    shift # past value
    ;;
    --default)
    DEFAULT=YES
    shift # past argument
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done

TEMPDIR="/tmp/tsi"
mkdir -p ${TEMPDIR}

CLUSTERINFO="${TEMPDIR}/clusterinfo.$$"
kubectl get cm -n kube-system cluster-info -o yaml > ${CLUSTERINFO}
PODINFO="${TEMPDIR}/podinfo.$$"
kubectl create -f ${FILE} -n ${NS} --dry-run=true -o yaml > ${PODINFO}
../../components/node-setup/secret-maker.sh ${CLUSTERINFO} ${PODINFO}
rm ${CLUSTERINFO} ${PODINFO}
