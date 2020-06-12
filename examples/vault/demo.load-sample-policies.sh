#!/bin/bash

## create help menu:
helpme()
{
  cat <<HELPMEHELPME

  Syntax: ${0} <vault_addr> <vault_token>
  Where:
    vault_addr - vault address (or ingress) in format http://vault.server:8200
    token      - vault root token to setup the plugin

Or make sure ROOT_TOKEN and VAULT_ADDR are set as environment variables.
export ROOT_TOKEN=
export VAULT_ADDR=(vault address in format http://vault.server:8200)

HELPMEHELPME
exit 1
}

# validate the arguments
if [[ "$1" != "" && "$2" != "" ]] ; then
  VAULT_ADDR="$1"
  ROOT_TOKEN="$2"
elif [[ "$ROOT_TOKEN" == "" || "$VAULT_ADDR" == "" ]] ; then
  echo "ROOT_TOKEN and VAULT_ADDR must be set"
  helpme
fi

echo "sample policies are now preloaded during the vault setup"
read -n 1 -s -r -p 'Press any key to continue'

docker run trustedseriviceidentity/tsi-util:latest load-sample-policies.sh ${VAULT_ADDR} ${ROOT_TOKEN}
