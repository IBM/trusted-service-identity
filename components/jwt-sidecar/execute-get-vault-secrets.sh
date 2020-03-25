#!/bin/bash

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
    WAIT_SEC=${SECRET_REFRESH_SEC}
  fi
  sleep "${WAIT_SEC}"
done
