#!/bin/bash

# this script requires https://github.com/duglin/tools/tree/master/demoscript
# or https://github.com/mrsabath/tools/tree/master/demoscript
declare DEMOFILE=/usr/local/bin/demoscript
if [ ! -f "$DEMOFILE" ]; then
    echo "$DEMOFILE does not exist."
    exit 1
fi
source "${DEMOFILE}"

AG_SOCK=${AG_SOCK:-"/run/spire/sockets/agent.sock"}
VAULT_ADDR=${VAULT_ADDR:-"http://tsi-kube01-9d995c4a8c7c5f281ce13d5467ff6a94-0000.us-south.containers.appdomain.cloud"}
VAULT_AUD=${VAULT_AUD:-"vault"}
VAULT_ROLE=${VAULT_ROLE:-"marsrole"}
VAULT_SECRET=${VAULT_SECRET:-"/v1/secret/data/my-super-secret"}
VAULT_DATA=${VAULT_DATA:-".data.data"}

# show the JWT token
doit "/opt/spire/bin/spire-agent api fetch jwt -audience $VAULT_AUD -socketPath $AG_SOCK"

# parse the JWT token
doit --noexec "/opt/spire/bin/spire-agent api fetch jwt -audience $VAULT_AUD -socketPath $AG_SOCK | sed -n '2p' | xargs > token.jwt"
/opt/spire/bin/spire-agent api fetch jwt -audience "$VAULT_AUD" -socketPath "$AG_SOCK" | sed -n '2p' | xargs > token.jwt

# use the JWT token to request VAULT token
JWT=$(cat token.jwt)
doit --noexec "curl --max-time 10 -s -o vout --request POST --data '{"'"jwt": "${JWT}", "role": "${VAULT_ROLE}"'" }' ${VAULT_ADDR}/v1/auth/jwt/login"
curl --max-time 10 -s -o vout  --request POST --data '{"jwt": "'"${JWT}"'", "role": "'"${VAULT_ROLE}"'" }' "${VAULT_ADDR}"/v1/auth/jwt/login

# parse the Vault token
doit --noexec 'TOKEN=$(cat vout | jq -r ".auth.client_token")'
TOKEN=$(cat vout | jq -r '.auth.client_token')

# use Vault token to request the secret
doit --noexec 'curl -s -H "X-Vault-Token: $TOKEN"'" ${VAULT_ADDR}${VAULT_SECRET} | jq -r '$VAULT_DATA'"
curl -s -H "X-Vault-Token: $TOKEN" "${VAULT_ADDR}${VAULT_SECRET}" | jq -r "$VAULT_DATA"
