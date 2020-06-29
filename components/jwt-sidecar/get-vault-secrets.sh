#!/bin/bash

SECOUTDIR="/usr/share/secrets"
JWTFILE="/jwt/token"
# SECREQFILE - Secret Request File from Pod Annotation
SECREQFILE="/pod-metadata/tsi-secrets"
LOGINFAIL="Vault Login Failure!"
TIMEOUT="504 Gateway Time-out"

# validate if VAULT_ADDR env. variable is set
if [ "$VAULT_ADDR" == "" ]; then
  echo "VAULT_ADDR must be set"
  exit 1
fi

# make sure that JWT file exists
if [ ! -s "$JWTFILE" ]; then
   echo "$JWTFILE does not exist. Make sure Trusted Identity is setup correctly"
   exit 1
fi

# since annotations are provided in YAML format,
# convert YAML to JSON for easier manipulations
if [ ! -s "$SECREQFILE" ]; then
   echo "$SECREQFILE contains no data. Nothing to do"
   exit 1
fi
JSON=$(yq r -j "$SECREQFILE")

# the return values from this function are ignored
# we only use the echoed values
login()
{
  local ROLE=$1
  local TOKEN
  local RESP

  LOGIN_FILE="/tmp/login.$$"
  TOKEN=$(cat $JWTFILE)

  # enforce the timeout to 10 seconds:
  # For testing timeout:
  # VAULT_ADDR=http://slowwly.robertomurray.co.uk/delay/15000/url/${VAULT_ADDR}
  SC=$(curl --max-time 10 -s -w "%{http_code}" -o $LOGIN_FILE --request POST --data '{"jwt": "'"${TOKEN}"'", "role": "'"${ROLE}"'"}' "${VAULT_ADDR}"/v1/auth/trusted-identity/login 2> /dev/null)
  local RT=$?

  RESP=$(cat $LOGIN_FILE)
  rm -f $LOGIN_FILE

  # return value for curl timeout is 28

  if [[ "$RT" == "28" ]]; then
    echo "$TIMEOUT"
    return 1
  fi

  if [[ "$SC" == "200" ]]; then
    echo "$RESP"
    return 0
  elif [[ "$RESP" == *"$TIMEOUT"* ]]; then
    echo "$TIMEOUT"
    return 1
  else
    echo "$LOGINFAIL"
    return 1
  fi
}

## create help menu:
helpme()
{
  cat <<HELPMEHELPME
Make sure VAULT_ADDR environment variable is set.
export VAULT_ADDR=(vault address is in format http://vault.server:8200)

HELPMEHELPME
}

# run secret retrieval and output results to specified location
run()
{
  # SECNAME=${SECNAME}, CONSTRAINTS=${CONSTR}, LOCPATH=${LOCPATH}
  local SECNAME=$1
  local CONSTR=$2
  local LOCPATH=$3
  local SECFILE="${SECOUTDIR}/${LOCPATH}/${SECNAME}"

  # local-path must start with "tsi-secrets"
  if [[ ${LOCPATH} != "tsi-secrets" ]] && [[ ${LOCPATH} != "/tsi-secrets" ]] && [[ ${LOCPATH} != /tsi-secrets/* ]] && [[ ${LOCPATH} != tsi-secrets/* ]]; then
    echo "ERROR: invalid local-path requested: $LOCPATH"
    return 1
  fi

  # There are 2 steps to obtain the secret:
  #   1. Login with Vault Role to obtain a token. Vault responds with claims
  #      associated with thie Role.
  #   2. Using claims associated with the Role, build the Vault Path to the
  #      given secret.

  # convert CONSTRAINTS into Vault Roles and Vault Paths:
  ROLE=
  VAULT_PATH=

  case $CONSTR in
    # TODO: this should be more dynamic instead of string comparison.
    # e.g. parse the values, trim, lowercase and perhaps sort alphabetically ??
      "region")
          # echo "# using policy $CONSTR"
          ROLE="tsi-role-r"
          VAULT_PATH="tsi-r"
          ;;
      "region,images")
          # echo "# using policy $CONSTR"
          ROLE="tsi-role-ri"
          VAULT_PATH="tsi-ri"
          ;;
      "region,cluster,namespace")
          #echo "# using policy $CONSTR"
          ROLE="tsi-role-rcn"
          VAULT_PATH="tsi-rcn"
          ;;
      "region,cluster-name,namespace,images")
          # echo "# using policy $CONSTR"
          ROLE="tsi-role-rcni"
          VAULT_PATH="tsi-rcni"
          ;;
      *) echo "# ERROR: invalid constraints requested: ${CONSTR}"
         return 1
         ;;
  esac

  # first login with 'secret.role' and JWT to obtain VAULT_TOKEN
  RESP=$(login "${ROLE}")
  if [ "$RESP" == "$LOGINFAIL" ]; then
    echo "Login to Vault failed!"
    rm -rf "${SECFILE}"
    return 1
  fi
  if [ "$RESP" == "$TIMEOUT" ]; then
    echo "Vault timeout!"
    return 1
  fi

  export VAULT_TOKEN=$(echo $RESP | jq -r '.auth.client_token')

  # Then parse the response to get other attributes associated
  # with this token.
  # Doublequotes required when the key name contains '-'
  REGION=$(echo $RESP | jq -r '.auth.metadata."region"')
  CLUSTER=$(echo $RESP | jq -r '.auth.metadata."cluster-name"')
  IMGSHA=$(echo $RESP | jq -r '.auth.metadata.images')
  NS=$(echo $RESP | jq -r '.auth.metadata.namespace')

  #echo "Getting $SECNAME from Vault $VAULT_PATH and output to $LOCPATH"
  if [ "$VAULT_PATH" == "tsi-rcni" ]; then
    CMD="${VAULT_ADDR}/v1/secret/data/${VAULT_PATH}/${REGION}/${CLUSTER}/${NS}/${IMGSHA}/${SECNAME}"
  elif [ "$VAULT_PATH" == "tsi-r" ]; then
    CMD="${VAULT_ADDR}/v1/secret/data/${VAULT_PATH}/${REGION}/${SECNAME}"
  elif [ "$VAULT_PATH" == "tsi-ri" ]; then
    CMD="${VAULT_ADDR}/v1/secret/data/${VAULT_PATH}/${REGION}/${IMGSHA}/${SECNAME}"
  elif [ "$VAULT_PATH" == "tsi-rcn" ]; then
    CMD="${VAULT_ADDR}/v1/secret/data/${VAULT_PATH}/${REGION}/${CLUSTER}/${NS}/${SECNAME}"
  else
    echo "Unknown Vault path value!"
    rm -rf "${SECFILE}"
    return 1
  fi

  # CMD="vault kv get -format=json secret/tsi-rcni/${REGION}/${CLUSTER}/${NS}/${IMGSHA}/${SECNAME}"
  # vault command:
  #  vault kv get -format=json secret/tsi-rcni/eu-de/ti-test/trusted-identity/f36b6d491e0a62cb704aea74d65fabf1f7130832e9f32d0771de1d7c727a79cc/dummy
  # is equivalent of:
  #  curl -X GET -H "X-Vault-Token: $(vault print token)" ${VAULT_ADDR}/v1/secret/data/tsi-rcni/eu-de/ti-test/trusted-identity/f36b6d491e0a62cb704aea74d65fabf1f7130832e9f32d0771de1d7c727a79cc/dummy

  # get the result in JSON format, then convert to string
  # Result can be also an error like this:
  #    No value found at secret/data/tsi-rcni/eu-de/ti-test1/trusted-identity/a8725beade10de172ec0fdbc683/dummyx
  RESULT_FILE="/tmp/result.$$"

  SC=$(curl --max-time 10 -s -w "%{http_code}" -H "X-Vault-Request: true" -H "X-Vault-Token: ${VAULT_TOKEN}" -o ${RESULT_FILE}  ${CMD})
  local RT=$?
  JRESULT=$(cat ${RESULT_FILE})
  rm -f ${RESULT_FILE}

  if [[ "${RT}" == "28" ]]; then
    echo "Timeout occured for SECNAME=${SECNAME}"
    return 1
  fi

  if [[ "${RT}" != "0" ]]; then
    echo "Unknow error occured for SECNAME=${SECNAME}, HTTP status: ${SC}, curl return: ${RT}, CMD: ${CMD}, RESULT: ${JRESULT}"
    return 1
  fi

  if [[ "$SC" == "200" ]]; then
    # echo "Vault command successful! RT: $RT"
    RESULT=$(echo $JRESULT | jq -c '.data.data')
    RT=$?
    if [ "$RT" == "0" ]; then
      mkdir -p "${SECOUTDIR}/${LOCPATH}"
      echo "$RESULT" > "${SECFILE}"
    else
      echo "Parsing vault response failed. Result: $JRESULT"
      rm -rf "${SECFILE}"
      return 1
    fi
  else
    echo "Vault command failed for SECNAME=${SECNAME}, HTTP status: ${SC}, CMD: $CMD, RESULT: $JRESULT"
    rm -rf "${SECFILE}"
    return 1
  fi
  echo "Processing secret: ${SECNAME} with constrains: $CONSTR successful"
} # .. end of run()

for row in $(echo "${JSON}" | jq -c '.[]' ); do
  # for each requested secret parse its attributes
  SECNAME=$(echo "$row" | jq -r '."tsi.secret/name"')
  CONSTR=$(echo "$row" | jq -r '."tsi.secret/constraints"')
  LOCPATH=$(echo "$row" | jq -r '."tsi.secret/local-path"')

  # then run secret retrieval from Vault
  run "$SECNAME" "$CONSTR" "$LOCPATH"
  RT=$?
  if [ "$RT" != "0" ]; then
    echo "Error processing secret SECNAME=${SECNAME}, CONSTRAINTS=${CONSTR}, LOCPATH=${LOCPATH}"
  fi
done
