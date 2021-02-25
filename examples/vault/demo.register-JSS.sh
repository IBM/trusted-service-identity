#!/bin/bash
SCRIPT_PATH=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
TSI_VERSION=$(cat ${SCRIPT_PATH}/../../tsi-version.txt)

TEMPDIR=$(mktemp -d /tmp/tsi.XXX)

## create help menu:
helpme()
{
  cat <<HELPMEHELPME

Syntax: ${0} <vault_token> <vault_addr> <TSI_namespace>
Where:
  vault_token      - vault root token to setup the plugin
  vault_addr - vault address (or ingress) in format http://vault.server:8200
  TSI_namespace  - if different than trusted-identity (optional)

Currently:
   ROOT_TOKEN=${ROOT_TOKEN}
   VAULT_ADDR=${VAULT_ADDR}

HELPMEHELPME
}

cleanup()
{
  rm -rf ${TEMPDIR}
}

# this function registers individual nodes
register()
{
  nodeIP=$($kk get pod $1 --output=jsonpath={.status.hostIP})
  echo "processing pod $1 for node IP $nodeIP"

  # get CSR for each node represented by pod-name
  CSR="${TEMPDIR}/$1.csr"
  # first obtain CSR from each node
  $kk exec -it $1 -- sh -c 'curl --max-time 5 -s $HOST_IP:5000/public/getCSR' > $CSR

  if [ ! -s "${CSR}" ]; then
    printf "\nFile ${CSR} does not exist or it is empty\n"
    cleanup
    exit 1
  fi

  # check for errors
  if [[ $(cat $CSR) == *errors* ]] ; then
    echo "Invalid CSR from JSS through pod $1. Please make sure tsi-node-setup was correctly executed on node: $nodeIP"
    cleanup
    exit 1
  fi

  X5C="${TEMPDIR}/$1.x5c"

  # process csr, register with vault, obtain x5c:
  RESP=$(docker run --rm --name=register-jss -v ${TEMPDIR}:/tmp/vault \
   --env "ROOT_TOKEN=${ROOT_TOKEN}" \
   --env "VAULT_ADDR=${VAULT_ADDR}" \
   tsidentity/tsi-util:"${TSI_VERSION}" /usr/local/bin/register-JSS.sh $1)
  RT=$?

  if [ "$RT" != "0" ]; then
    printf "Error occurred registering JSS: ${RESP}\n"
    cleanup
    exit 1
  fi
  printf "${RESP}" > "${X5C}"

  # cleanup CSR
  rm "${CSR}"

  # cat "$X5C"
  # copy the x5c file to the setup pod:
  $kk cp "$X5C" $1:/tmp/x5c
  RT=$?
  if [ $RT -ne 0 ] ; then
     echo "$X5C file could not be copied to $1:/tmp/x5c"
     cleanup
     exit 1
  fi

  # cleanup x5c
  rm "${X5C}"

  # echo "on the pod: "
  # $kk exec -it $1 -- sh -c 'cat /tmp/x5c'
  # using the copied x5c post the content to JSS server via setup-pod
  RESP=$($kk exec -it $1 -- sh -c 'curl -X POST --max-time 5 -s -H "Content-Type: application/json" -d @/tmp/x5c ${HOST_IP}:5000/public/postX5c')
  #RESP=$(curl -X POST -H "Content-Type: application/json" -d @x5c ${JSS_ADDR}/public/postX5c)
  echo $RESP
  echo "processing $1 for node: $nodeIP completed."
  # Take both output certificates, comma separated move to JSS as 'x5c' format:
  # based on spec: https://tools.ietf.org/html/rfc7515#appendix-B
  # ["MIIE3jCCA8agAwIBAgICAwEwDQYJKoZIhvcNAQEFBQAwYzELMAkGA1UEBhMCVVM
  #   ...
  #   H0aBsXBTWVU+4=","MIIE+zCC....wCW/POuZ6lcg5Ktz885hZo+L7tdEy8W9ViH0Pd"]
}

if [ ! "$1" == "" ] ; then
  export ROOT_TOKEN=$1
fi
if [ ! "$2" == "" ] ; then
  export VAULT_ADDR=$2
fi
kk="kubectl -n trusted-identity"
if [ ! "$3" == "" ] ; then
  kk="kubectl -n $3"
fi

# validate the arguments
if [[ "$1" == "-?" || "$1" == "-h" || "$1" == "--help" ]] ; then
  helpme
#check if token exists:
elif [[ "$ROOT_TOKEN" == "" || "$VAULT_ADDR" == "" ]] ; then
  echo "ROOT_TOKEN or VAULT_ADDR not set"
  helpme
  cleanup
  exit 1
else
  # get the list of all 'ti-node-setup' pods for each node instance
  # select only Running instances, to eliminate "Terminating" (helm operations)
  PODS=$($kk get pods --selector=app=ti-node-setup --field-selector=status.phase=Running --output=jsonpath={.items..metadata.name})
  if [ -z "$PODS" ];  then
        echo "ERROR!: There are no running 'ti-node-setup' pods. Cannot register JSS. Run 'helm install charts/tsi-node-setup'"
  else
      for n in ${PODS}
      #for n in $(kubectl -n trusted-identity get pods --selector=app=ti-node-setup -o custom-columns=NAME:.metadata.name,IP:.status.hostIP)
        do
          # for each pod representing a node, execute JSS node registration.
          # echo "Processing $n pod..."
          register $n
        done
  fi
fi

cleanup
