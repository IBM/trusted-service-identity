#!/bin/bash
SCRIPT_PATH=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
TSI_VERSION=$(cat ${SCRIPT_PATH}/../../tsi-version.txt)

## create help menu:
helpme()
{
  cat <<HELPMEHELPME

Syntax: ${0} <vault_addr> <vault_namespace>
Where:
  vault_addr - vault address in format http://vault.server:8200
  vault_namespace - if different than trusted-identity (optional)

HELPMEHELPME
}

setupVault()
{
  # remove any previously set VAULT_TOKEN, that overrides ROOT_TOKEN in Vault client
  export VAULT_TOKEN=

  # get the id of the vault container:
  VAULTPOD=$($kk get po | grep tsi-vault- | grep Running | awk '{print $1}')
  if [ "$VAULTPOD" == "" ]; then
     echo "No running Vault container in this namespace. Perhaps Vault is running in a different location"
     echo "Please validate by running the following command: "
     echo "      $kk get po | grep tsi-vault- | grep Running"
     exit 1
  fi

  # get the vault token and validate the connection:
  ROOT_TOKEN=$($kk logs "$VAULTPOD" | grep "Root Token" | cut -d' ' -f3)
  vault login -no-print "${ROOT_TOKEN}"
  RT=$?
  if [ $RT -ne 0 ] ; then
     echo "ROOT_TOKEN is not set correctly"
     echo "ROOT_TOKEN=${ROOT_TOKEN}"
     exit 1
  fi

  export SHA256
  SHA256=$($kk exec "$VAULTPOD" /usr/bin/sha256sum /plugins/vault-plugin-auth-ti-jwt | cut -d' ' -f1)
  # another way to obtain this SHA, use a local plugin created by the build process
  # assuming it is identical to the one one deployed in Vault container.
  # SHA256=$(shasum -a 256 "${PWD}/pkg/linux_amd64/${PLUGIN}" | cut -d' ' -f1)
  if [ "$SHA256" == "" ]; then
     echo "Failed to obtain plugin SHA256 from the Vault container. Please check if the container is operational"
     exit 1
  fi

  docker run trustedseriviceidentity/tsi-util:${TSI_VERSION} vault-setup.sh ${SHA256} ${ROOT_TOKEN} ${VAULT_ADDR}
  }


if [ ! "$1" == "" ] ; then
  export VAULT_ADDR=$1
fi

kk="kubectl -n trusted-identity"
if [ ! "$2" == "" ] ; then
  kk="kubectl -n $2"
fi

# validate the arguments
if [[ "$1" == "-?" || "$1" == "-h" || "$1" == "--help" ]] ; then
  helpme
#check if token exists:
elif [[ "$VAULT_ADDR" == "" ]] ; then
  echo "VAULT_ADDR not set"
  helpme
  exit 1
else
  setupVault
fi
