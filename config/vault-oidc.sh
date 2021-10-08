#!/bin/bash

OIDC_URL=${OIDC_URL:-$1}
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

Syntax: ${0} <OIDC_URL> <ROOT_TOKEN> <VAULT_ADDR>
Where:
  OIDC_URL    - OIDC URL (https://) (optional, if set as env. var)
  ROOT_TOKEN  - Vault root token to setup the plugin (optional, if set as env. var)
  VAULT_ADDR  - Vault address in format http://vault.server:8200 (optional, if set as env. var)

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
  vault write auth/jwt/config oidc_discovery_url=$OIDC_URL default_role=“dev”
  RT=$?
  if [ $RT -ne 0 ] ; then
     echo " 'vault write auth/jwt/config oidc_discovery_url=' command failed"
     echo "jwt maybe already enabled?"
     read -n 1 -s -r -p 'Press any key to continue'
     #exit 1
  fi

  # Define a policy my-dev-policy that will be assigned to a dev role that we’ll create in the next step.
  cat > vault-policy.hcl <<EOF
  path "secret/data/db-config.json" {
     capabilities = ["read"]
  }
EOF

  # write policy
  vault policy write my-db-policy ./vault-policy.hcl

# bound_subject does not allow using wildcards
# so we use bound_claims instead
  cat > role.json <<EOF
  {
      "role_type":"jwt",
      "user_claim": "sub",
      "bound_audiences": "vault",
      "bound_claims_type": "glob",
      "bound_claims": {
          "sub":"spiffe://openshift.space-x.com/region/*/cluster_name/*/ns/*/sa/*/pod_name/apps-*"
      },
      "token_ttl": "24h",
      "token_policies": "my-db-policy"
  }
EOF

  vault write auth/jwt/role/dbrole -<role.json
  vault read auth/jwt/role/dbrole
}

footer() {

  cat << EOF
create the secret in Vault (e.g.):
   create a file config.json
   vault kv put secret/db-config.json @config.json

Then start the workload container and get inside:

  kubectl -n default create -f examples/spire/mars-spaceX.yaml
  kubectl -n default exec -it <container id> -- sh

Once inside:
  # get the JWT token, and export it as JWT env. variable:
  bin/spire-agent api fetch jwt -audience vault -socketPath /run/spire/sockets/agent.sock

  # setup env. variables:
  export JWT=
  export ROLE=dbrole
  export VAULT_ADDR=$VAULT_ADDR

  # using this JWT to login with vault and get a token:
EOF

 echo "  curl --max-time 10 -s -o out --request POST --data '{" '"jwt": "'"'"'"${JWT}"'"'"'", "role": "'"'"'"${ROLE}"'"'"'"}'"' "'"${VAULT_ADDR}"/v1/auth/jwt/login'
 echo # empty line
 echo "  # get the client_token from the response"
 echo '  TOKEN=$(cat out | jq -r ' "'.auth.client_token')"
 echo '  curl -s -H "X-Vault-Token: $TOKEN" $VAULT_ADDR/v1/secret/data/db-config.json' " | jq -r '.data.data'"
}

# validate the arguments
if [[ "$1" == "-?" || "$1" == "-h" || "$1" == "--help" ]] ; then
  helpme
  exit 0
fi

# Make sure the OIDC_URL parameter is set
if [[ "$OIDC_URL" == "" ]] ; then
  echo "OIDC_URL must be set"
  helpme
  exit 1
fi

# when paramters provider, overrid the env. variables
if [[ "$3" != "" ]] ; then
  export OIDC_URL="$1"
  export ROOT_TOKEN="$2"
  export VAULT_ADDR="$3"
elif [[ "$ROOT_TOKEN" == "" || "$VAULT_ADDR" == "" ]] ; then
  echo "ROOT_TOKEN and VAULT_ADDR must be set"
  helpme
  exit 1
fi

setupVault
footer
