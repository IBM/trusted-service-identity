#!/bin/bash

IDSOUTDIR="/usr/share/secrets"
JWTFILE="/jwt/token"
# IDSREQFILE - Identities request file from Pod Annotation
IDSREQFILE="/pod-metadata/tsi-identities"

# when we decide to pass the Keycloak address on cluster level:
# validate if KEYCLOAK_ADDR env. variable is set
# if [ "$KEYCLOAK_ADDR" == "" ]; then
#   echo "KEYCLOAK_ADDR must be set"
#   exit 1
# fi

# make sure that JWT file exists
if [ ! -s "$JWTFILE" ]; then
   echo "$JWTFILE does not exist. Make sure Trusted Identity is setup correctly"
   exit 1
fi

# since annotations are provided in YAML format,
# convert YAML to JSON for easier manipulations
if [ ! -s "$IDSREQFILE" ]; then
   echo "$IDSREQFILE contains no data. Nothing to do"
   exit 1
fi
JSON=$(yq r -j "$IDSREQFILE")
if [ "$?" != "0" ]; then
  echo "Error parsing $IDSREQFILE file. Incorrect format"
  exit 1
fi

# the return values from this function are ignored
# we only use the echoed values
run()
{
  # example of the realm token URL:
  # "${KEYCLOAK_ADDR}/auth/realms/hello-world-authz/protocol/openid-connect/token"
  local KEYCLOAK_TOKEN_URL=$1
  local K_LOCAL=$2
  local LOCPATH=${K_LOCAL:-"tsi-secrets/identities"}
  local JWTFILE="/jwt/token"
  local TOKEN_RESP=$(mktemp /tmp/token-resp.XXX)

  # local-path must start with "tsi-secrets"
  if [[ ${LOCPATH} != "tsi-secrets" ]] && [[ ${LOCPATH} != "/tsi-secrets" ]] && [[ ${LOCPATH} != /tsi-secrets/* ]] && [[ ${LOCPATH} != tsi-secrets/* ]]; then
     echo "ERROR: invalid local-path requested: $LOCPATH"
     echo "Local path must start with /tsi-secrets"
     return 1
   fi
  local IDSOUTDIR=${IDSOUTDIR}/${LOCPATH}/

  SC=$(curl --max-time 10 -s -w "%{http_code}" -o $TOKEN_RESP --location --request POST \
  ${KEYCLOAK_TOKEN_URL} --header ': ' --header 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'client_id=tsi-client' --data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:uma-ticket' \
  --data-urlencode "tsi_token=$(cat $JWTFILE)" --data-urlencode 'audience=tsi-client' 2> /dev/null)
  local RT=$?

  # return value for curl timeout is 28
  if [[ "$RT" == "28" ]]; then
    echo "Timout while getting Keycloak token"
    rm $TOKEN_RESP
    return 1
  fi

  if [[ "$RT" != "0" ]]; then
    echo "Unknown error getting Keycloak token"
    cat $TOKEN_RESP
    rm $TOKEN_RESP
    return 1
  fi

  if [ "$SC" != "200" ]; then
    echo "Error getting Keycloak token"
    cat $TOKEN_RESP
    rm $TOKEN_RESP
    return 1
  fi

  RESP=$(cat $TOKEN_RESP)
  # rm -f $TOKEN_RESP
  mkdir -p ${IDSOUTDIR}
  mv $TOKEN_RESP ${IDSOUTDIR}/access_token
  # REF_TOK=$(echo $RESP | jq -r '.refresh_token')
  # ACCESS_TOK=$(echo $RESP | jq -r '.access_token')
  # echo $ACCESS_TOK | cut -d"." -f2 | sed 's/\./\n/g' | base64 --decode | jq
  echo $RESP | jq -r '.access_token' | cut -d"." -f2 | base64 --decode  | jq  '.'  > ${IDSOUTDIR}/acces_token.txt
}

## create help menu:
helpme()
{
  cat <<HELPMEHELPME
Syntax: $0

HELPMEHELPME
}


for row in $(echo "${JSON}" | jq -c '.[]' ); do
# for each requested identities parse its attributes
 KEYCLOAK_ADDR=$(echo "$row" | jq -r '."tsi.keycloak/token-url"')
 KEYCLOAK_PATH=$(echo "$row" | jq -r '."tsi.keycloak/local-path"')
 if [ "$KEYCLOAK_PATH" == "null" ]; then
	 KEYCLOAK_PATH=""
 fi
  # then run identity retrieval from Keycloak
  run $KEYCLOAK_ADDR $KEYCLOAK_PATH
  RT=$?
  if [ "$RT" != "0" ]; then
    echo "Error processing identities KEYCLOAK_ADDR=${KEYCLOAK_ADDR}"
    exit 1
  fi
done
