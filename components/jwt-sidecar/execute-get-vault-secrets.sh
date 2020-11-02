#!/bin/bash

# For debbugging and manually retrieving the vault secrets:
#  VAULT_ADDR is already defined on the sidecar. You can modify the token and
# the role
#   curl --request POST --data '{"jwt": "'"$(cat /jwt/token)"'", "role": "'tsi-role-r'"}' "${VAULT_ADDR}"/v1/auth/trusted-identity/login | jq
# using the response above extract the auth.client_token and set as VAULT_TOKEN
#   export VAULT_TOKEN=$(echo $RESP | jq -r '.auth.client_token')
# Or, if results are successful, use all-in-one:
#   export VAULT_TOKEN=$(curl --request POST --data '{"jwt": "'"$(cat /jwt/token)"'", "role": "'tsi-role-r'"}' "${VAULT_ADDR}"/v1/auth/trusted-identity/login | jq -r '.auth.client_token')
# now ready to retrieve the secret:
#   vault kv get -format=json secret/tsi-r/eu-de/mysecret4

JWTFILE="/jwt/token"
SECREQFILE="/pod-metadata/tsi-secrets"

# set the initial wait to 10 seconds
# once the vault secret is retrieved successfully, switch to
# provided parameter
WAIT_SEC=10

# when script is running in init initContainer, attempt obtaining secrets only few times
MAX_EXEC=5
COUNTER=0

while true
do
  # first we should wait for the token to be available
  if [ ! -s "$JWTFILE" ]; then
      echo "$JWTFILE does not exist yet. Let's wait for it. Please make sure the JSS in initalized."
      while [ ! -s "$JWTFILE" ]; do
        sleep 5
      done
  fi

  # get the secret definitions
  if [ ! -s "$SECREQFILE" ]; then
    echo "$SECREQFILE does not exist or empty."

    if $IS_SIDECAR; then
        echo "Nothing to do. Waiting..."
        while [ ! -s "$SECREQFILE" ]; do
          sleep 5
        done
    else
      # if the script is running in initContainer, there is no need to block
      # when no secrets are needed
      echo "Nothing to do. Exiting ..."
      exit 0
    fi

  fi

  /usr/local/bin/get-vault-secrets.sh
  RT=$?
  # When script is running as sidecar, run it forever
  if $IS_SIDECAR; then
    if [ "$RT" == "0" ]; then
      # introduce the random wait value from 1 to 30 seconds
      RAND_WAIT=$((1 + RANDOM % 30))
      WAIT_SEC=$((${SECRET_REFRESH_SEC} + RAND_WAIT))
      echo "Waiting $WAIT_SEC seconds ..."
    fi
  else
    # when it's running as initContainer, exit after successful transaction
    if [ "$RT" == "0" ]; then
      echo "Secrets successfully executed!"
      exit 0
    fi
    if [[ "$COUNTER" -gt "$MAX_EXEC" ]]; then
      echo "$COUNTER unsuccessful attempts to get secret. Exiting..."
      exit 1
    fi
    ((COUNTER++))
  fi
  sleep "${WAIT_SEC}"
done
