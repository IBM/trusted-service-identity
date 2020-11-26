#!/bin/bash

JWTFILE="/jwt/token"
IDSREQFILE="/pod-metadata/tsi-identities"

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

  # get the identity definitions
  if [ ! -s "$IDSREQFILE" ]; then
    echo "$IDSREQFILE does not exist or empty."

    if $IS_SIDECAR; then
        echo "Nothing to do. Waiting..."
        while [ ! -s "$IDSREQFILE" ]; do
          sleep 5
        done
    else
      # if the script is running in initContainer, there is no need to block
      # when no secrets are needed
      echo "Nothing to do. Exiting ..."
      exit 0
    fi

  fi

  /usr/local/bin/get-keycloak-identities.sh
  RT=$?
  # When script is running as sidecar, run it forever
  if $IS_SIDECAR; then
    if [ "$RT" == "0" ]; then
      # introduce the random wait value from 1 to 30 seconds
      RAND_WAIT=$((1 + RANDOM % 30))
      WAIT_SEC=$((${IDENTITY_REFRESH_SEC} + RAND_WAIT))
      echo "Waiting $WAIT_SEC seconds ..."
    fi
  else
    # when it's running as initContainer, exit after successful transaction
    if [ "$RT" == "0" ]; then
      echo "Keycloak identities successfully executed!"
      exit 0
    fi
    if [[ "$COUNTER" -gt "$MAX_EXEC" ]]; then
      echo "$COUNTER unsuccessful attempts to get Keycloak identities. Exiting..."
      exit 1
    fi
    ((COUNTER++))
  fi
  sleep "${WAIT_SEC}"
done
