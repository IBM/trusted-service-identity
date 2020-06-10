#!/bin/bash

docker_cmd="docker --version"
if [[ ! $(eval ${docker_cmd}) ]]; then
  echo "docker installation required to proceed"
  echo "(https://docs.docker.com/get-docker/)"
  exit 1
fi

TEMPDIR="/tmp/tsi"
mkdir -p ${TEMPDIR}

CLUSTERINFO="${TEMPDIR}/clusterinfo.$$"
kubectl get cm -n kube-system cluster-info -o yaml > ${CLUSTERINFO}

docker run -v ${CLUSTERINFO}:/tmp/clusterinfo \
docker.io/trustedseriviceidentity/tsi-util:latest /usr/local/bin/getClusterInfo.sh /tmp/clusterinfo

rm ${CLUSTERINFO}
