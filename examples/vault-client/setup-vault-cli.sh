#!/bin/bash
JWTFILE=/jwt-tokens/token
if [ ! -s "$JWTFILE" ]; then
   echo "$JWTFILE does not exist. Make sure Trusted Identity is setup correctly"
   exit 1
fi

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
 export TOKEN=$(cat ${JWTFILE})
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
elif [ "$1" == "" ] ; then
  export ROLE="${VAULT_ROLE}"
  getToken
else
  export ROLE="$1"
  getToken
fi
