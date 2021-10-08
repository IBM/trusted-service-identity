#!/bin/bash

SOCKETFILE=${SOCKETFILE:-"/run/spire/sockets/agent.sock"}
CFGFILE=${CFGFILE:-"/run/db/config.json"}
ROLE=${ROLE:-"dbrole"}
VAULT_ADDR=${VAULT_ADDR:-"http://tsi-vault-tsi-vault.space-x04-9d995c4a8c7c5f281ce13d5467ff6a94-0000.eu-de.containers.appdomain.cloud"}

WAIT=30
RESP="/tmp/resp"
TOKEN="/tmp/token.jwt"
VTOKEN="/tmp/vtoken"

while true
 do
  # make sure the socket file exists before requesting a token
  while [ ! -S ${SOCKETFILE} ]; do
    sleep 5
  done
  /opt/spire/bin/spire-agent api fetch jwt -audience vault -socketPath /run/spire/sockets/agent.sock > $RESP
  if [ "$?" == "1" ]; then
    continue
  else
    cat $RESP | sed -n '2p' | xargs > $TOKEN
  fi

# For use with AWS S3:
# the audience must be switched to 'mys3'
# /opt/spire/bin/spire-agent api fetch jwt -audience mys3 -socketPath /run/spire/sockets/agent.sock > $RESP
# AWS_ROLE_ARN=arn:aws:iam::581274594392:role/mars-mission-role AWS_WEB_IDENTITY_TOKEN_FILE=token.jwt aws s3 cp s3://mars-spire/db-config.json config.json
# mv config.json $CFGFILE
# exit 0

  export JWT=$(cat $TOKEN)

  curl --max-time 10 -s -o out --request POST --data '{ "jwt": "'"${JWT}"'", "role": "'"${ROLE}"'"}' "${VAULT_ADDR}"/v1/auth/jwt/login
  TOKEN=$(cat out | jq -r  '.auth.client_token')
  curl --max-time 10 -s -H "X-Vault-Token: $TOKEN" $VAULT_ADDR/v1/secret/data/db-config.json  | jq -r '.data.data' > $VTOKEN
  RT=$?

  if [ "$RT" == "0" ]; then
    mv $VTOKEN $CFGFILE
    exit 0
  fi

  sleep "$WAIT"
done
