#!/bin/bash

# NS - a TSI namespace (where the tsi-setup daemonset is deployed)
TSINS="trusted-identity"

## create help menu:
helpme()
{
  cat <<HELPMEHELPME
  This script builds a template for injecting secrets to Vault
  using TSI-node-setup daemonset

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

SYSINFO="/tmp/sysinfo.$$"
kubectl get cm -n kube-system cluster-info -o yaml > ${SYSINFO}
PODINFO="/tmp/podinfo.$$"
kubectl create -f ${FILE} -n ${NS} --dry-run=true -o yaml > ${PODINFO}

kk="kubectl -n ${TSINS}"
# get the first `tsi-node-setup` pod in Running state
SETPOD=$(${kk} get po | grep tsi-node-setup | grep 'Running' | awk '{print $1}' |  sed -n 1p )
if [[ "$SETPOD" == "" ]]; then
  echo "Required tsi-node-setup daemonset is not running"
  echo "For more information, please visit: "
  echo "  https://github.com/IBM/trusted-service-identity/examples/vault/README.md#secrets"
  exit 1
fi

# copy the files into the pod
${kk} cp ${SYSINFO} ${SETPOD}:/tmp/sysinfo
${kk} cp ${PODINFO} ${SETPOD}:/tmp/podinfo
${kk} exec -it $SETPOD -- sh -c '/usr/local/bin/secret-maker.sh /tmp/sysinfo /tmp/podinfo'
rm ${SYSINFO} ${PODINFO}
