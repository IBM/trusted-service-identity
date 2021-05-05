#!/bin/bash -x

# https://spiffe.io/docs/latest/keyless/vault/readme/
# https://www.vaultproject.io/docs/auth/jwt_oidc_providers
# https://learn.hashicorp.com/tutorials/vault/oidc-auth?in=vault/auth-methods

#ibmcloud plugin install cloud-object-storage
STATEDIR=${STATEDIR:-/tmp}
SPIRE_SERVER=${SPIRE_SERVER:-$1}
ROOT_TOKEN=${ROOT_TOKEN:-$2}
VAULT_ADDR=${VAULT_ADDR:-$3}
export VAULT_ADDR=$VAULT_ADDR
export ROOT_TOKEN=$ROOT_TOKEN
# remove any previously set VAULT_TOKEN, that overrides ROOT_TOKEN in Vault client
export VAULT_TOKEN=

## create help menu:
helpme()
{
  cat <<HELPMEHELPME

Syntax: ${0} <SPIRE server> <token> <vault_addr>
Where:
  SPIRE server  - SPIRE Server (https://) (optional, if set as env. var)
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
     echo "VAULT_ADDR=${VAULT_ADDR}"
     exit 1
  fi


  # # vault status
  # vault secrets enable pki
  # RT=$?
  # if [ $RT -ne 0 ] ; then
  #    echo " 'vault secrets enable pki' command failed"
  #    echo "pki maybe already enabled?"
  #    read -n 1 -s -r -p 'Press any key to continue'
  #    #exit 1
  # fi


  # Enable JWT authentication
  vault auth enable jwt
  RT=$?
  if [ $RT -ne 0 ] ; then
     echo " 'vault auth enable jwt' command failed"
     echo "jwt maybe already enabled?"
     read -n 1 -s -r -p 'Press any key to continue'
     #exit 1
  fi


  # Connect OIDC - Set up our OIDC Discovery URL,
  vault write auth/jwt/config oidc_discovery_url=$SPIRE_SERVER default_role=“dev”
  RT=$?
  if [ $RT -ne 0 ] ; then
     echo " 'vault write auth/jwt/config oidc_discovery_url=' command failed"
     echo "jwt maybe already enabled?"
     read -n 1 -s -r -p 'Press any key to continue'
     #exit 1
  fi

  # Define a policy my-dev-policy that will be assigned to a dev role that we’ll create in the next step.
  cat > vault-policy.hcl <<EOF
  path "secret/data/my-super-secret" {
     capabilities = ["read"]
  }
EOF

  # write policy
  vault policy write my-dev-policy ./vault-policy.hcl

  #vault write auth/jwt/role/dev role_type=jwt user_claim=sub bound_audiences=TESTING bound_subject=spiffe://example.org/ns/default/sa/default token_ttl=24h token_policies=my-dev-policy

# bound_subject does not allow using wildcards
# so we use bound_claims instead
  cat > role.json <<EOF
  {
      "role_type":"jwt",
      "user_claim": "sub",
      "bound_audiences": "vault",
      "bound_claims_type": "glob",
      "bound_claims": {
          "sub":"spiffe://openshift.space-x.com/eu-*/*/*/elon-musk/mars-mission-main/*"
      },
      "token_ttl": "24h",
      "token_policies": "my-dev-policy"
  }
EOF

  vault write auth/jwt/role/eurole -<role.json

  vault read auth/jwt/role/eurole

  echo "vault kv put secret/my-super-secret test=123"

  apk add jq
  # curl --request POST --data @payload.json http://tsi-kube01-9d995c4a8c7c5f281ce13d5467ff6a94-0000.us-south.containers.appdomain.cloud/v1/auth/jwt/login
  # export JWT=
  # export ROLE=eurole
  # export VAULT_ADDR=http://tsi-kube01-9d995c4a8c7c5f281ce13d5467ff6a94-0000.us-south.containers.appdomain.cloud
  # SC=$(curl --max-time 10 -s -w "%{http_code}" -o out --request POST --data '{"jwt": "'"${JWT}"'", "role": "'"${ROLE}"'"}' "${VAULT_ADDR}"/v1/auth/jwt/login 2> /dev/null)

TOKEN=$(cat out | jq -r '.auth.client_token')
curl -H "X-Vault-Token: $TOKEN" $VAULT_ADDR/v1/secret/data/my-super-secret
curl -s -H "X-Vault-Token: $TOKEN" $VAULT_ADDR/v1/secret/data/my-super-secret | jq
 -r '.data.data'

  # export TOKEN=
  # curl -H "X-Vault-Token: $TOKEN" $VAULT_ADDR/v1/secret/data/my-super-secret

  # Increase the TTL by tuning the secrets engine. The default value of 30 days may
  # be too short, so increase it to 1 year:
  #vault secrets tune -max-lease-ttl=8760h pki
  #vault delete pki/root

  # create internal root CA
  # expire in 100 years
  #export OUT
  #OUT=$(vault write pki/root/generate/internal common_name=${COMMON_NAME} \
  #    ttl=876000h -format=json)
  # echo "$OUT"

  # capture the public key as plugin-config.json
  # CERT=$(echo "$OUT" | jq -r '.["data"].issuing_ca'| awk '{printf "%s\\n", $0}')
  # echo "{ \"jwt_validation_pubkeys\": \"${CERT}\" }" > ${CONFIG}
  #
  # # register the trusted-identity plugin
  # vault write /sys/plugins/catalog/auth/vault-plugin-auth-ti-jwt sha_256="${SHA256}" command="vault-plugin-auth-ti-jwt"
  # RT=$?
  # if [ $RT -ne 0 ] ; then
  #    echo " 'vault write /sys/plugins/catalog/auth/vault-plugin-auth-ti-jwt ...' command failed"
  #    exit 1
  # fi
  # # useful for debugging:
  # # vault read sys/plugins/catalog/auth/vault-plugin-auth-ti-jwt -format=json
  #
  # # then enable this plugin
  # vault auth enable -path="trusted-identity" -plugin-name="vault-plugin-auth-ti-jwt" plugin
  # RT=$?
  # if [ $RT -ne 0 ] ; then
  #    echo " 'vault auth enable plugin' command failed"
  #    exit 1
  # fi
  #
  # export MOUNT_ACCESSOR
  # MOUNT_ACCESSOR=$(curl -sS --header "X-Vault-Token: ${ROOT_TOKEN}"  --request GET "${VAULT_ADDR}/v1/sys/auth" | jq -r '.["trusted-identity/"].accessor')
  #
  # # configure plugin using the Issuing CA created internally above
  # curl -sS --header "X-Vault-Token: ${ROOT_TOKEN}"  --request POST --data @${CONFIG} "${VAULT_ADDR}/v1/auth/trusted-identity/config"
  # RT=$?
  # if [ $RT -ne 0 ] ; then
  #    echo "failed to configure trusted-identity plugin"
  #    exit 1
  # fi

  # for debugging only:
  # CONFIG=$(curl -sS --header "X-Vault-Token: ${ROOT_TOKEN}"  --request GET "${VAULT_ADDR}/v1/auth/trusted-identity/config" | jq)
  # echo "*** $CONFIG"
  }

# if [ ! "$1" == "" ] ; then
#   export ROOT_TOKEN=$1
# fi
# if [ ! "$2" == "" ] ; then
#   export VAULT_ADDR=$2
# fi
#
# # validate the arguments
# if [[ "$1" == "-?" || "$1" == "-h" || "$1" == "--help" ]] ; then
#   helpme
# fi
#
# # SHA256 of the TSI plugin must be provided
# if [[ "$1" == "" ]] ; then
#   helpme
#   exit 1
# else
#   SHA256="$1"
# fi
#

# Make sure the SPIRE_SERVER parameter is set
if [[ "$SPIRE_SERVER" == "" ]] ; then
  echo "SPIRE_SERVER must be set"
  helpme
  exit 1
fi


# when paramters provider, overrid the env. variables
if [[ "$3" != "" ]] ; then
  export SPIRE_SERVER="$1"
  export ROOT_TOKEN="$2"
  export VAULT_ADDR="$3"
elif [[ "$ROOT_TOKEN" == "" || "$VAULT_ADDR" == "" ]] ; then
  echo "ROOT_TOKEN and VAULT_ADDR must be set"
  helpme
  exit 1
fi

setupVault
