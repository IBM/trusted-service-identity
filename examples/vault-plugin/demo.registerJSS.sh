#!/bin/bash

## create help menu:
helpme()
{
  cat <<HELPMEHELPME

Syntax: ${0} <vault_token> <vault_addr>
Where:
  token      - vault root token to setup the plugin
  vault_addr - vault address (or ingress) in format http://vault.server:8200

Currently:
   ROOT_TOKEN=${ROOT_TOKEN}
   VAULT_ADDR=${VAULT_ADDR}

HELPMEHELPME
}
kk="kubectl -n trusted-identity"

# this function registers individual nodes
register()
{
  nodeIP=$($kk get pod $1 --output=jsonpath={.status.hostIP})
  echo "processing pod $1 for node IP $nodeIP"

  # get CSR for each node represented by pod-name
  CSR=$1.csr
  # first obtain CSR from each node
  $kk exec -it $1 -- sh -c 'curl $HOST_IP:5000/public/getCSR' > $CSR
  #cat $CSR
  # check for errors
  if [[ $(cat $CSR) == *errors* ]] ; then
    echo "Invalid CSR from JSS through pod $1. Please make sure tsi-node-setup was correctly executed on node: $nodeIP"
    exit 1
  fi

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

  X5C="$1.x5c"
  # create an intermedate certificate for 50 years
  vault write pki/root/sign-intermediate csr=@$CSR format=pem_bundle ttl=438000h -format=json > out
  CERT=$(cat out | jq -r '.["data"].certificate' | grep -v '\-\-\-')
  CHAIN=$(cat out | jq -r '.["data"].issuing_ca' | grep -v '\-\-\-')
  echo "[\"${CERT}\",\"${CHAIN}\"]" > "$X5C"

  # cleanup CSR
  rm "${CSR}"

  # cat "$X5C"
  # copy the x5c file to the setup pod:
  $kk cp "$X5C" $1:/tmp/x5c
  RT=$?
  if [ $RT -ne 0 ] ; then
     echo "$X5C file could not be copied to $1:/tmp/x5c"
     exit 1
  fi

  # cleanup x5c
  rm "${X5C}"
  # echo "on the pod: "
  # $kk exec -it $1 -- sh -c 'cat /tmp/x5c'
  # using the copied x5c post the content to JSS server via setup-pod
  RESP=$($kk exec -it $1 -- sh -c 'curl -X POST -H "Content-Type: application/json" -d @/tmp/x5c ${HOST_IP}:5000/public/postX5c')
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

# validate the arguments
if [[ "$1" == "-?" || "$1" == "-h" || "$1" == "--help" ]] ; then
  helpme
#check if token exists:
elif [[ "$ROOT_TOKEN" == "" || "$VAULT_ADDR" == "" ]] ; then
  echo "ROOT_TOKEN or VAULT_ADDR not set"
  helpme
else
  # get the list of all 'ti-node-setup' pods for each node instance
  # select only Running instances, to eliminate "Terminating" (helm operations)
  PODS=$(kubectl -n trusted-identity get pods --selector=app=ti-node-setup --field-selector=status.phase=Running --output=jsonpath={.items..metadata.name})
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
