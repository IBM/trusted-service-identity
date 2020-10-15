#!/bin/bash
SCRIPT_PATH=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
TSI_VERSION=$(cat ${SCRIPT_PATH}/../tsi-version.txt)

docker_cmd="docker --version"
if [[ ! $(eval ${docker_cmd}) ]]; then
  echo "docker installation required to proceed"
  echo "(https://docs.docker.com/get-docker/)"
  exit 1
fi

TEMPDIR=$(mktemp -d /tmp/tsi.XXX)

CLUSTERINFO="${TEMPDIR}/clusterinfo.$$"
kubectl get cm -n kube-system cluster-info -o yaml > ${CLUSTERINFO}

docker run --rm -v ${CLUSTERINFO}:/tmp/clusterinfo \
docker.io/trustedseriviceidentity/tsi-util:${TSI_VERSION} /usr/local/bin/getClusterInfo.sh /tmp/clusterinfo

rm ${CLUSTERINFO}
