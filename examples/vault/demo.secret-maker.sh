#!/bin/bash
SCRIPT_PATH=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
TSI_VERSION=$(cat ${SCRIPT_PATH}/../../tsi-version.txt)

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

docker_cmd="docker --version"

if [[ ! $(eval ${docker_cmd}) ]]; then
  echo "docker installation required to proceed"
  echo "(https://docs.docker.com/get-docker/)"
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

# check if the pod deployment file exists:
if [ ! -f "$FILE" ]; then
    echo "File $FILE does not exist"
    exit 1
fi

TEMPDIR="/tmp/tsi"
mkdir -p ${TEMPDIR}

CLUSTERINFO="${TEMPDIR}/clusterinfo.$$"
kubectl get cm -n kube-system cluster-info -o yaml > ${CLUSTERINFO}
PODINFO="${TEMPDIR}/podinfo.$$"
kubectl create -f ${FILE} -n ${NS} --dry-run=true -o yaml > ${PODINFO}

docker run -v ${CLUSTERINFO}:/tmp/clusterinfo -v ${PODINFO}:/tmp/podinfo \
docker.io/trustedseriviceidentity/tsi-util:${TSI_VERSION} /usr/local/bin/secret-maker.sh /tmp/clusterinfo /tmp/podinfo

rm ${CLUSTERINFO} ${PODINFO}
