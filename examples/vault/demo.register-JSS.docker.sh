#!/bin/bash
SCRIPT_PATH=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
TSI_VERSION=$(cat ${SCRIPT_PATH}/../../tsi-version.txt)
TSI_VERSION=${TSI_VERSION:-"v1.7.7"}

TEMPDIR=$(mktemp -d /tmp/tsi.XXX)

## create help menu:
helpme()
{
  cat <<HELPMEHELPME

Syntax: ${0} <container name>
  Where:
    container name - owner of the scr file
  Required environment variables:
    ROOT_TOKEN - vault root token to setup the plugin
    VAULT_ADDR - vault address (or ingress) in format http://vault.server:8200
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
  # get CSR for each node represented by pod-name
  CSR="${TEMPDIR}/$1.csr"
  # docker exec -it $1 sh -c 'curl $HOST_IP:5000/public/getCSR' > $CSR
  SC=$(curl --max-time 10 -s -w "%{http_code}" -o "${CSR}" localhost:5000/public/getCSR)
  if [ "$SC" != "200" ]; then
    printf "\nError while getting CSR. Make sure the public JSS interface is enabled.\n"
    cleanup
    return 1
  fi

  if [ ! -s "${CSR}" ]; then
    printf "\nFile ${CSR} does not exist or it is empty\n"
    cleanup
    exit 1
  fi

  # check for errors
  if [[ $(cat $CSR) == *errors* ]] ; then
    #echo "Invalid CSR from JSS through pod $1. Please make sure tsi-node-setup was correctly executed on node: $nodeIP"
    printf "\nInvalid CSR from JSS for the pod $1. Please make sure tsi-node-setup was correctly executed\n"
    cleanup
    exit 1
  fi

  X5C="${TEMPDIR}/$1.x5c"
  OUT="${TEMPDIR}/$1.out"

  RESP=$(docker run --rm --name=register-jss -v ${TEMPDIR}:/tmp/vault \
   --env "ROOT_TOKEN=${ROOT_TOKEN}" \
   --env "VAULT_ADDR=${VAULT_ADDR}" \
   trustedseriviceidentity/tsi-util:"${TSI_VERSION}" /usr/local/bin/register-JSS.sh $1)
  RT=$?

  if [ "$RT" != "0" ]; then
    printf "Error occurred registering JSS: ${RESP}\n"
    cleanup
    exit 1
  fi
  printf "${RESP}" > "${X5C}"

  #  RESP=$($kk exec -it $1 -- sh -c 'curl -X POST -H "Content-Type: application/json" -d @/tmp/x5c ${HOST_IP}:5000/public/postX5c')
  SC=$(curl -X POST --max-time 10 -s -w "%{http_code}" -o ${OUT} -H "Content-Type: application/json" -d "@${X5C}" localhost:5000/public/postX5c)
  cat ${OUT}
  if [ "$SC" != "200" ]; then
    printf "\nHTTP Code=${SC}\n Error registering x5c with JSS server. Make sure the public JSS interface is enabled.\n"
    cleanup
    return 1
  fi
  printf "\nRegistration of $1 with JSS server completed successfully\n"

  # cleanup CSR
  rm "${CSR}"
  rm "${X5C}"
  rm "${OUT}"
}

if [ "$1" == "" ] ; then
  helpme
  cleanup
  exit 1
fi

# validate the arguments
if [[ "$1" == "-?" || "$1" == "-h" || "$1" == "--help" ]] ; then
  helpme
#check if token exists:
elif [[ "$ROOT_TOKEN" == "" || "$VAULT_ADDR" == "" ]] ; then
  printf "ROOT_TOKEN or VAULT_ADDR not set"
  helpme
  cleanup
  exit 1
else
  register $1
fi

cleanup
