#!/bin/bash

#ibmcloud plugin install cloud-object-storage
export PLUGIN="vault-plugin-auth-ti-jwt"
COMMON_NAME="trusted-identity.ibm.com"
CONFIG="/tmp/plugin-config.json"

## create help menu:
helpme()
{
  cat <<HELPMEHELPME

Syntax: ${0} <vault-plugin-sha> <token> <vault_addr>
Where:
  vault-plugin-sha - SHA 256 of the TSI Vault plugin (required)
  token         - vault root token to setup the plugin (optional, if set as env. var)
  vault_addr    - vault address in format http://vault.server:8200 (optional, if set as env. var)

HELPMEHELPME
}

setupVault()
{
  vault login -no-print "${ROOT_TOKEN}"
  RT=$?
  if [ $RT -ne 0 ] ; then
     echo "ROOT_TOKEN is not correctly set"
     echo "ROOT_TOKEN=${ROOT_TOKEN}"
     exit 1
  fi
  # remove any previously set VAULT_TOKEN, that overrides ROOT_TOKEN in Vault client
  export VAULT_TOKEN=

  # vault status
  vault secrets enable pki
  RT=$?
  if [ $RT -ne 0 ] ; then
     echo " 'vault secrets enable pki' command failed"
     echo "maybe already set?"
     read -n 1 -s -r -p 'Press any key to continue'
     #exit 1
  fi
  # Increase the TTL by tuning the secrets engine. The default value of 30 days may
  # be too short, so increase it to 1 year:
  vault secrets tune -max-lease-ttl=8760h pki
  vault delete pki/root

  # create internal root CA
  # expire in 100 years
  export OUT
  OUT=$(vault write pki/root/generate/internal common_name=${COMMON_NAME} \
      ttl=876000h -format=json)
  # echo "$OUT"

  # capture the public key as plugin-config.json
  CERT=$(echo "$OUT" | jq -r '.["data"].issuing_ca'| awk '{printf "%s\\n", $0}')
  echo "{ \"jwt_validation_pubkeys\": \"${CERT}\" }" > ${CONFIG}

  # register the trusted-identity plugin
  vault write /sys/plugins/catalog/auth/vault-plugin-auth-ti-jwt sha_256="${SHA256}" command="vault-plugin-auth-ti-jwt"
  RT=$?
  if [ $RT -ne 0 ] ; then
     echo " 'vault write /sys/plugins/catalog/auth/vault-plugin-auth-ti-jwt ...' command failed"
     exit 1
  fi
  # useful for debugging:
  # vault read sys/plugins/catalog/auth/vault-plugin-auth-ti-jwt -format=json

  # then enable this plugin
  vault auth enable -path="trusted-identity" -plugin-name="vault-plugin-auth-ti-jwt" plugin
  RT=$?
  if [ $RT -ne 0 ] ; then
     echo " 'vault auth enable plugin' command failed"
     exit 1
  fi

  export MOUNT_ACCESSOR
  MOUNT_ACCESSOR=$(curl -sS --header "X-Vault-Token: ${ROOT_TOKEN}"  --request GET "${VAULT_ADDR}/v1/sys/auth" | jq -r '.["trusted-identity/"].accessor')

  # configure plugin using the Issuing CA created internally above
  curl -sS --header "X-Vault-Token: ${ROOT_TOKEN}"  --request POST --data @${CONFIG} "${VAULT_ADDR}/v1/auth/trusted-identity/config"
  RT=$?
  if [ $RT -ne 0 ] ; then
     echo "failed to configure trusted-identity plugin"
     exit 1
  fi

  # for debugging only:
  # CONFIG=$(curl -sS --header "X-Vault-Token: ${ROOT_TOKEN}"  --request GET "${VAULT_ADDR}/v1/auth/trusted-identity/config" | jq)
  # echo "*** $CONFIG"
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
fi

# SHA256 of the TSI plugin must be provided
if [[ "$1" == "" ]] ; then
  helpme
  exit 1
else
  SHA256="$1"
fi

# validate the Vault arguments
if [[ "$3" != "" ]] ; then
  export ROOT_TOKEN="$2"
  export VAULT_ADDR="$3"
elif [[ "$ROOT_TOKEN" == "" || "$VAULT_ADDR" == "" ]] ; then
  echo "ROOT_TOKEN and VAULT_ADDR must be set"
  helpme
  exit 1
fi

setupVault
# once the vault is setup, load the sample policies
load-sample-policies.sh
