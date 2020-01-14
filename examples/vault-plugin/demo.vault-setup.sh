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
  token      - vault root token to setup the plugin (optional, if set as ROOT_TOKEN)
  vault_addr - vault address in format http://vault.server:8200

HELPMEHELPME
}

setupVault()
{
  vault login "${ROOT_TOKEN}"
  RT=$?
  if [ $RT -ne 0 ] ; then
     echo "ROOT_TOKEN is not correctly set"
     echo "ROOT_TOKEN=${ROOT_TOKEN}"
     exit 1
  fi
  # remove any previously set VAULT_TOKEN, that overrides ROOT_TOKEN in Vault client
  export VAULT_TOKEN=

  vault status
  vault secrets enable pki
  RT=$?
  if [ $RT -ne 0 ] ; then
     echo " 'vault secrets enable pki' command failed"
     echo "maybe already set?"
     exit 1
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
  echo "$OUT"

  # capture the public key as plugin-config.json
  CERT=$(echo "$OUT" | jq -r '.["data"].issuing_ca'| awk '{printf "%s\\n", $0}')
  echo "{ \"jwt_validation_pubkeys\": \"${CERT}\" }" > ${CONFIG}

  # obtain the SHA256 for the plugin
  # if the deployed image has the same binary as the one on your system, use the
  # following method:
  export SHA256
  SHA256=$(kubectl -n trusted-identity exec $(kubectl -n trusted-identity get po | grep tsi-vault-| awk '{print $1}') /usr/bin/sha256sum /plugins/vault-plugin-auth-ti-jwt | cut -d' ' -f1)
  # another way to obtain this SHA, use a local plugin created by the build process
  # assuming it is identical to the one one deployed in Vault container.
  # SHA256=$(shasum -a 256 "${PWD}/pkg/linux_amd64/${PLUGIN}" | cut -d' ' -f1)
  if [ "$SHA256" == "" ]; then
     echo "Failed to obtain plugin SHA256 from the Vault container. Please check if the container is operational"
     exit 1
  fi

  # register the trusted-identity plugin
  vault write sys/plugins/catalog/auth/vault-plugin-auth-ti-jwt sha_256="${SHA256}" command="vault-plugin-auth-ti-jwt"
  RT=$?
  if [ $RT -ne 0 ] ; then
     echo " 'vault write sys/plugins/catalog/auth/vault-plugin-auth-ti-jwt ...' command failed"
     exit 1
  fi
  vault read sys/plugins/catalog/auth/vault-plugin-auth-ti-jwt -format=json
  # then enable this plugin
  vault auth enable -path="trusted-identity" -plugin-name="vault-plugin-auth-ti-jwt" plugin
  RT=$?
  if [ $RT -ne 0 ] ; then
     echo " 'vault auth enable plugin' command failed"
     exit 1
  fi

  export MOUNT_ACCESSOR
  MOUNT_ACCESSOR=$(curl --header "X-Vault-Token: ${ROOT_TOKEN}"  --request GET "${VAULT_ADDR}/v1/sys/auth" | jq -r '.["trusted-identity/"].accessor')

  # configure plugin using the Issuing CA created internally above
  curl --header "X-Vault-Token: ${ROOT_TOKEN}"  --request POST --data @${CONFIG} "${VAULT_ADDR}/v1/auth/trusted-identity/config"
  RT=$?
  if [ $RT -ne 0 ] ; then
     echo "failed to configure trusted-identity plugin"
     exit 1
  fi

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
# elif [ ! -f "${PWD}/pkg/linux_amd64/${PLUGIN}" ]; then
#   echo "Plugin directory missing \"${PWD}/pkg/linux_amd64/${PLUGIN}\""
else
  setupVault "$1 $2"
fi
