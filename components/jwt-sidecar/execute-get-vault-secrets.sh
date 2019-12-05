#!/bin/bash

JWTFILE="/jwt/token"
SECREQFILE="/pod-metadata/tsi-secrets"

while true
 do
   if [ ! -s "$SECREQFILE" ]; then
      echo "$SECREQFILE does not exist or empty. Nothing to do. Waiting..."
   else
      if [ ! -s "$JWTFILE" ]; then
        echo "$JWTFILE does not exist yet. Let's wait for it..."
      else
        /usr/local/bin/get-vault-secrets.sh
      fi
   fi
  sleep "${SECRET_REFRESH_SEC}"
done
