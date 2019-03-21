#!/bin/bash

#ibmcloud plugin install cloud-object-storage
export PLUGIN="vault-plugin-auth-ti-jwt"

## create help menu:
helpme()
{
  cat <<HELPMEHELPME

Syntax: ${0} <token> <vault_addr>
Where:
  token      - vault root token to setup the plugin
  vault_addr - vault address in format http://vault.server:8200

HELPMEHELPME
}

setupVault()
{
  echo "Root Token: ${ROOT_TOKEN}"
  vault login ${ROOT_TOKEN}

  export SHA256=$(shasum -a 256 "${PWD}/pkg/linux_amd64/${PLUGIN}" | cut -d' ' -f1)
  vault write sys/plugins/catalog/auth/vault-plugin-auth-ti-jwt sha_256="${SHA256}" command="vault-plugin-auth-ti-jwt"
  vault auth enable -path="trusted-identity" -plugin-name="vault-plugin-auth-ti-jwt" plugin

  export MOUNT_ACCESSOR=$(curl --header "X-Vault-Token: ${ROOT_TOKEN}"  --request GET ${VAULT_ADDR}/v1/sys/auth | jq -r '.["trusted-identity/"].accessor')

  # configure plugin
  # obtain JWKS-PEM (plugin-config.json) from vTPM: curl http://vtpm-service:8012/getJWKS
  curl --header "X-Vault-Token: ${ROOT_TOKEN}"  --request POST --data @jwks.json ${VAULT_ADDR}/v1/auth/trusted-identity/config
  }

if [ ! "$1" == "" ] ; then
  export ROOT_TOKEN=$1
fi
if [ ! "$2" == "" ] ; then
  export VAULT_ADDR=$2
fi

# validate the arguments
if [[ "$1" == "-?" || "$1" == "-h" || "$1" == "--help" ]] ; then
  helpme
#check if token exists:
elif [[ "$ROOT_TOKEN" == "" || "$VAULT_ADDR" == "" ]] ; then
  echo "ROOT_TOKEN or VAULT_ADDR not set"
  helpme
elif [ ! -f "${PWD}/pkg/linux_amd64/${PLUGIN}" ]; then
  echo "Plugin directory missing \"${PWD}/pkg/linux_amd64/${PLUGIN}\""
else
  setupVault $1 $2
fi
