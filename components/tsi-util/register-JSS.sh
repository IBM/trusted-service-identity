#!/bin/bash

TEMPDIR="/tmp/tsi"
mkdir -p ${TEMPDIR}
export CSR_DIR=${CSR_DIR:-/tmp/vault}
#export CSR=${CSR:-${CSR_DIR}/csr}

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
Optional:
  CSR_DIR - local directory where the scr file stored
Currently:
   ROOT_TOKEN=${ROOT_TOKEN}
   VAULT_ADDR=${VAULT_ADDR}
   CSR_DIR=${CSR_DIR}
HELPMEHELPME
}

# this function registers individual nodes
register()
{
  CSR="${CSR_DIR}/$1.csr"
  if [ ! -s "${CSR}" ]; then
    echo "File ${CSR} do not exist or it is empty"
    helpme
    exit 1
  fi

  # check for errors
  if [[ $(cat ${CSR}) == *errors* ]] ; then
    echo "Invalid CSR from JSS for $1. Please make sure tsi-node-setup was correctly executed"
    exit 1
  fi

  # extract the X509v3 TSI fields:
  TSIEXT="${TEMPDIR}/$1.csr.tsi"
  openssl req -in "${CSR}" -noout -text |grep "URI:TSI" > $TSIEXT
  RT=$?
  if [ $RT -ne 0 ] ; then
    echo "Missing x509v3 URI:TSI extensions for cluter-name and region"
    rm "${TSIEXT}"
    exit 1
  fi

  # format:
  #     URI:TSI:cluster-name:my-cluster-name, URI:TSI:region:eu-de
  # remove the "URI:" prefix and leading spaces
  TSI_URI=$(cat $TSIEXT | sed 's/URI://g' | sed 's/  //g')

  # echo "Root Token: ${ROOT_TOKEN}"
  vault login -no-print ${ROOT_TOKEN}
  RT=$?
  if [ $RT -ne 0 ] ; then
     echo "ROOT_TOKEN is not correctly set"
     echo "ROOT_TOKEN=${ROOT_TOKEN}"
     exit 1
  fi
  # remove any previously set VAULT_TOKEN, that overrides ROOT_TOKEN in Vault client
  export VAULT_TOKEN=

  X5C="${TEMPDIR}/$1.x5c"
  OUT="${TEMPDIR}/out.$$"

  # create an intermedate certificate for 50 years
  vault write pki/root/sign-intermediate csr=@$CSR format=pem_bundle ttl=438000h uri_sans="$TSI_URI" -format=json > ${OUT}
  CERT=$(cat ${OUT} | jq -r '.["data"].certificate' | grep -v '\-\-\-')
  CHAIN=$(cat ${OUT} | jq -r '.["data"].issuing_ca' | grep -v '\-\-\-')
  echo "[\"${CERT}\",\"${CHAIN}\"]" > "$X5C"

  # cleanup CSR
  # rm "${CSR}"
  rm "${TSIEXT}"
  rm "${OUT}"

  cat "$X5C"

  # cleanup x5c
  rm "${X5C}"

  # # using the copied x5c post the content to JSS server via setup-pod
  # RESP=$($kk exec -it $1 -- sh -c 'curl -X POST -H "Content-Type: application/json" -d @/tmp/x5c ${HOST_IP}:5000/public/postX5c')
  # #RESP=$(curl -X POST -H "Content-Type: application/json" -d @x5c ${JSS_ADDR}/public/postX5c)
  # echo $RESP
  # echo "processing $1 for node: $nodeIP completed."
  # # Take both output certificates, comma separated move to JSS as 'x5c' format:
  # # based on spec: https://tools.ietf.org/html/rfc7515#appendix-B
  # # ["MIIE3jCCA8agAwIBAgICAwEwDQYJKoZIhvcNAQEFBQAwYzELMAkGA1UEBhMCVVM
  # #   ...
  # #   H0aBsXBTWVU+4=","MIIE+zCC....wCW/POuZ6lcg5Ktz885hZo+L7tdEy8W9ViH0Pd"]
}

if [ -z "${VAULT_ADDR}" ]; then
  echo "VAULT_ADDR is not set"
  helpme
  exit 1
fi

if [ -z "${ROOT_TOKEN}" ]; then
  echo "ROOT_TOKEN is not set"
  helpme
  exit 1
fi

# validate the arguments
if [[ "$1" == "-?" || "$1" == "-h" || "$1" == "--help" ]] ; then
  helpme
else
  register $1
fi
