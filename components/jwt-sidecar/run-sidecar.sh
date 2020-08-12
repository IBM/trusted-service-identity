#!/usr/bin/env bash

/usr/local/bin/execute-get-token.sh &
/usr/local/bin/execute-get-vault-secrets.sh
RT=$?

if ! $IS_SIDECAR; then
  if [ "$RT" == "0" ]; then
    echo "All good!"
    exit 0
  else
    echo "Unsuccessful retrieve"
    exit 1
  fi
fi
