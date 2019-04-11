#!/bin/bash

#ibmcloud plugin install cloud-object-storage
export PLUGIN="vault-plugin-auth-ti-jwt"
COMMON_NAME="trusted-identity.ibm.com"
CONFIG="plugin-config.json"

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
  vault login "${ROOT_TOKEN}"
  # remove any previously set VAULT_TOKEN, that overrides ROOT_TOKEN in Vault client
  export VAULT_TOKEN=

  vault status
  vault secrets enable pki
  # Increase the TTL by tuning the secrets engine. The default value of 30 days may
  # be too short, so increase it to 1 year:
  vault secrets tune -max-lease-ttl=8760h pki
  vault delete pki/root

  # create internal root CA
  # expire in 100 years
  export OUT
  OUT=$(vault write pki/root/generate/internal common_name=${COMMON_NAME} \
      ttl=876000h -format=json)
  echo "$OUT"

  CERT=$(echo "$OUT" | jq -r '.["data"].issuing_ca'| awk '{printf "%s\\n", $0}')
  echo "{ \"jwt_validation_pubkeys\": \"${CERT}\" }" > ${CONFIG}

  # obtain the SHA256 for the plugin
  # if the deployed image has the same binary as the one on your system, use the
  # following method:
  export SHA256
  SHA256=$(shasum -a 256 "${PWD}/pkg/linux_amd64/${PLUGIN}" | cut -d' ' -f1)
  # otherwise, you can obtain it by going directly to the vault server:
  # export SHA256=$(kubectl -n trusted-identity exec $(kubectl -n trusted-identity get po | grep ti-vault-| awk '{print $1}') /usr/bin/sha256sum /plugins/vault-plugin-auth-ti-jwt | cut -d' ' -f1)

  vault write sys/plugins/catalog/auth/vault-plugin-auth-ti-jwt sha_256="${SHA256}" command="vault-plugin-auth-ti-jwt"
  vault read sys/plugins/catalog/auth/vault-plugin-auth-ti-jwt -format=json
  vault auth enable -path="trusted-identity" -plugin-name="vault-plugin-auth-ti-jwt" plugin

  export MOUNT_ACCESSOR
  MOUNT_ACCESSOR=$(curl --header "X-Vault-Token: ${ROOT_TOKEN}"  --request GET "${VAULT_ADDR}/v1/sys/auth" | jq -r '.["trusted-identity/"].accessor')

  # configure plugin using the Issuing CA created internally above
  curl --header "X-Vault-Token: ${ROOT_TOKEN}"  --request POST --data @${CONFIG} "${VAULT_ADDR}/v1/auth/trusted-identity/config"
  curl --header "X-Vault-Token: ${ROOT_TOKEN}"  --request GET "${VAULT_ADDR}/v1/auth/trusted-identity/config"
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
  setupVault "$1 $2"
fi
