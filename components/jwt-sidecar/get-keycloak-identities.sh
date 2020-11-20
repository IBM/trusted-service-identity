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
  local AUD=$3
  local JWTFILE="/jwt/token"
  local TOKEN_RESP=$(mktemp /tmp/token-resp.XXX)
  local FILENAME="access_token.$3.$COUNT"

  # local-path must start with "tsi-secrets"
  if [[ ${LOCPATH} != "tsi-secrets" ]] && [[ ${LOCPATH} != "/tsi-secrets" ]] && [[ ${LOCPATH} != /tsi-secrets/* ]] && [[ ${LOCPATH} != tsi-secrets/* ]]; then
     echo "ERROR: invalid local-path requested: $LOCPATH"
     echo "Local path must start with /tsi-secrets"
     return 1
   fi
  local IDSOUTDIR=${IDSOUTDIR}/${LOCPATH}

  # Sample format for requesting the access token:
  # curl --location --request POST 'http://<keycloak-server>/auth/realms/tsi-realm/protocol/openid-connect/token' \
  # --header 'Content-Type: application/x-www-form-urlencoded' \
  # --data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:uma-ticket' \
  # --data-urlencode 'audience=tsi-client' \
  # --data-urlencode 'client_id=tsi-client' \
  # --data-urlencode "tsi_token=$(cat /jwt/token)"

  # Sample format for requesting the public key from Keycloak:
  # curl --location --request GET 'http://<keycloak-server>/auth/realms/tsi-realm/protocol/openid-connect/certs' \
  # --header 'Content-Type: application/x-www-form-urlencoded' \
  # --data-urlencode --data-urlencode "tsi_token=$(cat /jwt/token)"

  SC=$(curl --max-time 10 -s -w "%{http_code}" -o $TOKEN_RESP --location --request POST \
  ${KEYCLOAK_TOKEN_URL} --header 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'client_id=tsi-client' --data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:uma-ticket' \
  --data-urlencode "tsi_token=$(cat $JWTFILE)" --data-urlencode "audience=$AUD" 2> /dev/null)
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
  mv $TOKEN_RESP ${IDSOUTDIR}/${FILENAME}
  # REF_TOK=$(echo $RESP | jq -r '.refresh_token')
  # ACCESS_TOK=$(echo $RESP | jq -r '.access_token')
  # echo $ACCESS_TOK | cut -d"." -f2 | sed 's/\./\n/g' | base64 --decode | jq
  echo $RESP | jq -r '.access_token' | cut -d"." -f2 | base64 --decode  | jq  '.'  > ${IDSOUTDIR}/${FILENAME}.txt
}

## create help menu:
helpme()
{
  cat <<HELPMEHELPME
Syntax: $0

HELPMEHELPME
}

ERR=0
COUNT=0
for row in $(echo "${JSON}" | jq -c '.[]' ); do
# for each requested identities parse its attributes
 KEYCLOAK_ADDR=$(echo "$row" | jq -r '."tsi.keycloak/token-url"')
 KEYCLOAK_PATH=$(echo "$row" | jq -r '."tsi.keycloak/local-path"')
 KEYCLOAK_AUDS=$(echo "$row" | jq -r '."tsi.keycloak/audiences"')
 if [ "$KEYCLOAK_PATH" == "null" ]; then
	 KEYCLOAK_PATH=""
 fi
 if [ "$KEYCLOAK_AUDS" == "null" ]; then
	 KEYCLOAK_AUDS="tsi-client"
 fi

 # audiences can be separated with comma
 auds=$(echo $KEYCLOAK_AUDS | tr "," "\n")
 for aud in $auds; do

    # then run identity retrieval from Keycloak
    run $KEYCLOAK_ADDR $KEYCLOAK_PATH $aud
    RT=$?
    if [ "$RT" != "0" ]; then
      echo "Error processing identities token-url=${KEYCLOAK_ADDR}, audiance=$aud, local-path=$KEYCLOAK_PATH"
      # if we want to end the init process in case of the failed attempt,
      # uncomment all the way to the end
      #  ERR=1
    fi
    # increase the counter
    COUNT=$((COUNT+1))
  done
  # if [ "$ERR" -ne 0 ]; then
  #   exit 1
  # fi
done
