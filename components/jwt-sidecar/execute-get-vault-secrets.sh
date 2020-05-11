#!/bin/bash

# For debbugging and manually retrieving the vault secrets:
#  VAULT_ADDR is already defined on the sidecar. You can modify the token and
# the role
#   curl --request POST --data '{"jwt": "'"$(cat /jwt/token)"'", "role": "'demo-r'"}' "${VAULT_ADDR}"/v1/auth/trusted-identity/login | jq
# using the response above extract the auth.client_token and set as VAULT_TOKEN
#   export VAULT_TOKEN=$(echo $RESP | jq -r '.auth.client_token')
# Or, if results are successful, use all-in-one:
#   export VAULT_TOKEN=$(curl --request POST --data '{"jwt": "'"$(cat /jwt/token)"'", "role": "'demo-r'"}' "${VAULT_ADDR}"/v1/auth/trusted-identity/login | jq -r '.auth.client_token')
# now ready to retrieve the secret:
#   vault kv get -format=json secret/ti-demo-r/eu-de/mysecret4

JWTFILE="/jwt/token"
SECREQFILE="/pod-metadata/tsi-secrets"

# set the initial wait to 10 seconds
# once the vault secret is retrieved successfully, switch to
# provided parameter
WAIT_SEC=10

while true
do
  if [ ! -s "$SECREQFILE" ]; then
    echo "$SECREQFILE does not exist or empty. Nothing to do. Waiting..."
    while [ ! -s "$SECREQFILE" ]; do
      sleep 5
    done
  fi

  if [ ! -s "$JWTFILE" ]; then
      echo "$JWTFILE does not exist yet. Let's wait for it. Please make sure the JSS in initalized."
      while [ ! -s "$JWTFILE" ]; do
        sleep 5
      done
  fi
  /usr/local/bin/get-vault-secrets.sh
  RT=$?
  if [ "$RT" == "0" ]; then
    # introduce the random wait value from 1 to 30 seconds
    RAND_WAIT=$((1 + RANDOM % 30))
    WAIT_SEC=$((${SECRET_REFRESH_SEC} + RAND_WAIT))
    echo "Waiting $WAIT_SEC seconds ..."
  fi
  sleep "${WAIT_SEC}"
done
