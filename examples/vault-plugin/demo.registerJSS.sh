#!/bin/bash

#ibmcloud plugin install cloud-object-storage
export PLUGIN="vault-plugin-auth-ti-jwt"

## create help menu:
helpme()
{
  cat <<HELPMEHELPME

Syntax: ${0} <vault_token> <vault_addr> <vtpm_addr>
Where:
  token      - vault root token to setup the plugin
  vault_addr - vault address (or ingress) in format http://vault.server:8200
  jss_addr   - JSS server address (or ingress) in format http://jss.server

Currently:
   ROOT_TOKEN=${ROOT_TOKEN}
   VAULT_ADDR=${VAULT_ADDR}
   JSS_ADDR=${JSS_ADDR}

HELPMEHELPME
}

register()
{
  # first obtain CSR from vTPM.
  curl ${JSS_ADDR}/public/getCSR > jss.csr
  if [[ $(cat jss.csr) == *errors* ]] ; then
    echo "Invalid CSR from JSS. Please make sure your Ingress is correctly set."
    echo "Test it via: 'curl ${JSS_ADDR}/public/getCSR'"
    exit 1
  fi
  echo "Root Token: ${ROOT_TOKEN}"
  vault login ${ROOT_TOKEN}
  RT=$?
  if [ $RT -ne 0 ] ; then
     echo "ROOT_TOKEN is not correctly set"
     echo "ROOT_TOKEN=${ROOT_TOKEN}"
     exit 1
  fi
  # remove any previously set VAULT_TOKEN, that overrides ROOT_TOKEN in Vault client
  export VAULT_TOKEN=

  # Obtain the CSR from vTPM. Connect to any container deployed in `trusted-identity`
  # namespace and get it using `curl http:/jss-service:8012/getCSR` > jss.csr
  # NOT THIS: curl localhost:5000/getJWKS | awk '{printf "%s\\n", $0}' > jwks.json

  #vault write pki/root/sign-intermediate csr=@jss.csr format=pem_bundle ttl=43800h

  # create a certificate for 50 years
  vault write pki/root/sign-intermediate csr=@jss.csr format=pem_bundle ttl=438000h -format=json > out
  CERT=$(cat out | jq -r '.["data"].certificate' | grep -v '\-\-\-')
  CHAIN=$(cat out | jq -r '.["data"].issuing_ca' | grep -v '\-\-\-')
  echo "[\"${CERT}\",\"${CHAIN}\"]" > x5c

  cat x5c
  RESP=$(curl -X POST -H "Content-Type: application/json" -d @x5c ${JSS_ADDR}/public/postX5c)
  echo $RESP

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
if [ ! "$3" == "" ] ; then
  export JSS_ADDR=$3
fi

# validate the arguments
if [[ "$1" == "-?" || "$1" == "-h" || "$1" == "--help" ]] ; then
  helpme
#check if token exists:
elif [[ "$ROOT_TOKEN" == "" || "$VAULT_ADDR" == "" || "$JSS_ADDR" == "" ]] ; then
  echo "ROOT_TOKEN, VAULT_ADDR or JSS_ADDR not set"
  helpme
else
  register
fi
