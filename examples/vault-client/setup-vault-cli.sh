#!/bin/bash

## create help menu:
helpme()
{
  cat <<HELPMEHELPME

Syntax: ${0} <role>
Where:
  role   - name of the vault role for this login

HELPMEHELPME
}

getToken()
{
 #validate the external parameters
 if [ "$1" == "" ] ; then
   export ROLE="${VAULT_ROLE}"
 else
   export ROLE="$1"
 fi

 export TOKEN=$(cat /jwt-tokens/token)
 # export VAULT_TOKEN=$(curl -s --request POST --data '{"jwt": "'"${TOKEN}"'", "role": "'"${ROLE}"'"}' ${VAULT_ADDR}/v1/auth/trusted-identity/login | jq -r '.auth.client_token')
 export RESP=$(curl -s --request POST --data '{"jwt": "'"${TOKEN}"'", "role": "'"${ROLE}"'"}' ${VAULT_ADDR}/v1/auth/trusted-identity/login)
 export VAULT_TOKEN=$(echo $RESP | jq -r '.auth.client_token')
 if [ "$VAULT_TOKEN" == "null" ] ; then
   echo "ERROR: $RESP"
 else
   echo "VAULT_TOKEN=$VAULT_TOKEN"
 fi
}

# validate the arguments
if [[ "$1" == "-?" || "$1" == "-h" || "$1" == "--help" ]] ; then
  helpme
#check if token exists:
elif [ ! -f "/jwt-tokens/token" ]; then
  echo "Token is missing '/jwt-tokens/token'"
else
  getToken
fi
