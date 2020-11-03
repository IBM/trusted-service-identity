#!/usr/bin/env bash

/usr/local/bin/execute-get-token.sh &

/usr/local/bin/execute-get-vault-secrets.sh
RT=$?
if ! $IS_SIDECAR; then
  if [ "$RT" == "0" ]; then
    echo "All good with secrets"
  else
    echo "Unsuccessful Vault retrieve"
    exit 1
  fi
fi
/usr/local/bin/execute-get-keycloak-identities.sh
RT=$?
if ! $IS_SIDECAR; then
  if [ "$RT" == "0" ]; then
    echo "All good with identities"
  else
    echo "Unsuccessful Keycloak retrieve"
    exit 1
  fi
fi
