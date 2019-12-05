#!/bin/bash

SECOUTDIR="/usr/share/secrets"
JWTFILE="/jwt/token"
# SECREQFILE - Secret Request File from Pod Annotation
SECREQFILE="/pod-metadata/tsi-secrets"
LOGINFAIL="Vault Login Failure!"

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


login()
{
local ROLE=$1
local TOKEN
local RESP
TOKEN=$(cat $JWTFILE)
RESP=$(curl --request POST --data '{"jwt": "'"${TOKEN}"'", "role": "'"${ROLE}"'"}' ${VAULT_ADDR}/v1/auth/trusted-identity/login 2> /dev/null)
# TODO we need better test if HTTP status code is 200
# using `curl --request POST -w "%{http_code}"`
# we can get HTTP code in a separate line, but it needs to be parsed, tested and stripped.
# if [[ "$RESP" == *200 ]]; then
#         echo "$RESP"
# else
#       echo "$LOGINFAIL"
# fi
#
local RT=$?
if [ "$RT" == "0" ]; then
     echo "$RESP"
else
  echo "$LOGINFAIL"
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
local SECNAME=$1
local ROLE=$2
local VAULT_PATH=$3
local SECOUT=$4

# first login with 'secret.role' and JWT to obtain VAULT_TOKEN
RESP=$(login "${ROLE}")
if [ "$RESP" == "$LOGINFAIL" ]; then
  echo "Login to Vault failed!"
  return 1
fi
export VAULT_TOKEN=$(echo $RESP | jq -r '.auth.client_token')

# Then parse the response to get other attributes associated
# with this token.
# Doublequotes required when the key name contains '-'
REGION=$(echo $RESP | jq -r '.auth.metadata."cluster-region"')
CLUSTER=$(echo $RESP | jq -r '.auth.metadata."cluster-name"')
IMGSHA=$(echo $RESP | jq -r '.auth.metadata.images')
NS=$(echo $RESP | jq -r '.auth.metadata.namespace')

echo "Getting $SECNAME from Vault $VAULT_PATH and output to $SECOUT"
if [ "$VAULT_PATH" == "secret/ti-demo-all" ]; then
	CMD="vault kv get -format=json ${VAULT_PATH}/${REGION}/${CLUSTER}/${NS}/${IMGSHA}/${SECNAME}"
elif [ "$VAULT_PATH" == "secret/ti-demo-r" ]; then
        CMD="vault kv get -format=json ${VAULT_PATH}/${REGION}/${SECNAME}"
elif [ "$VAULT_PATH" == "secret/ti-demo-n" ]; then
        CMD="vault kv get -format=json ${VAULT_PATH}/${REGION}/${CLUSTER}/${NS}/${SECNAME}"
else
    echo "Unknown Vault path value!"
    return 1
fi

#CMD="vault kv get -format=json secret/ti-demo-all/${REGION}/${CLUSTER}/${NS}/${IMGSHA}/${SECNAME}"
#vault kv get -format=json secret/ti-demo-all/eu-de/ti-test/trusted-identity/f36b6d491e0a62cb704aea74d65fabf1f7130832e9f32d0771de1d7c727a79cc/dummy | jq -c '.data.data'

# get the result in JSON format, then convert to string 
JRESULT=$($CMD)
RESULT=$(echo $JRESULT | jq -c '.data.data')

local RT=$?
if [ "$RT" == "0" ]; then
  echo "Test successful! RT: $RT"
  echo "Result: $RESULT"
  mkdir -p "${SECOUTDIR}/${SECOUT}"
  echo $RESULT > "${SECOUTDIR}/${SECOUT}/${SECNAME}"
else
  echo "Test failed: RT: $RT, CMD: $CMD"
fi
}


for row in $(echo "${JSON}" | jq -c '.[]' ); do
  # for each requested secret parse its attributes
 SECNAME=$(echo "$row" | jq -r '."tsi.secret/name"')
 ROLE=$(echo "$row" | jq -r '."tsi.secret/role"')
 VAULT_PATH=$(echo "$row" | jq -r '."tsi.secret/vault-path"')
 SECOUT=$(echo "$row" | jq -r '."tsi.secret/local-name"')

 # then run secret retrieval from Vault
 run "$SECNAME" "$ROLE" "$VAULT_PATH" "$SECOUT"
done
