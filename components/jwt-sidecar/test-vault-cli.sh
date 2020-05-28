#!/bin/bash

JWTFILE="/jwt/token"
LOGINFAIL="Vault Login Failure!"

# SECREQFILE - Secret Request File from Pod Annotation
#SECREQFILE="/pod-metadata/tsi-secrets"
VAULT_ROLE=demo

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

# sha-256 encoded file name based on the OS:
# if [[ "$OSTYPE" == "linux-gnu" ]]; then
#   # Linux
#   IMGSHA=$(echo -n "$IMG" | sha256sum | awk '{print $1}')
# elif [[ "$OSTYPE" == "darwin"* ]]; then
#   # Mac OSX
#   IMGSHA=$(echo -n "$IMG" | shasum -a 256 | awk '{print $1}')
# else
#   # Unknown.
#   echo "Unsupported plaftorm to execute this test. Set the IMGSHA environment"
#   echo "variable to represent sha 256 encoded name of the test image"
#   exit 1
# fi

test()
{
  local CMD=$1
  local EXPECT=$2
  local ID=$3
  $CMD >/dev/null 2> /dev/null
  local RT=$?

  if [ "$RT" == "$EXPECT" ]; then
    echo "$ID Test successful! RT: $RT"
  else
    echo "$ID Test failed: $CMD, RT: $RT, Expected: $EXPECT"
  fi
}

login()
{
  local ROLE=$1
  local TOKEN=$(cat $JWTFILE)
  local RESP=$(curl --request POST --data '{"jwt": "'"${TOKEN}"'", "role": "'"${ROLE}"'"}' ${VAULT_ADDR}/v1/auth/trusted-identity/login 2> /dev/null)
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
       echo $RESP
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

tests()
{
  echo "Testing the default $VAULT_ROLE role: "
  #export TOKEN=$(cat /jwt-tokens/token)
  #export VAULT_TOKEN=$(curl --request POST --data '{"jwt": "'"${TOKEN}"'", "role": "'"${VAULT_ROLE}"'"}' ${VAULT_ADDR}/v1/auth/trusted-identity/login | jq -r '.auth.client_token')
  RESP=$(login ${VAULT_ROLE})
  export VAULT_TOKEN=$(echo $RESP | jq -r '.auth.client_token')
  # doublequotes required when the key name contains '-'
  REGION=$(echo $RESP | jq -r '.auth.metadata."region"')
  CLUSTER=$(echo $RESP | jq -r '.auth.metadata."cluster-name"')
  IMGSHA=$(echo $RESP | jq -r '.auth.metadata.images')
  NS=$(echo $RESP | jq -r '.auth.metadata.namespace')


  test "vault kv get secret/ti-demo-all/${REGION}/${CLUSTER}/${NS}/${IMGSHA}/mysecret1" 0 A01
  test "vault kv get secret/ti-demo-all/${REGION}/${CLUSTER}/xxxx/${IMGSHA}/mysecret1" 2 A02
  test "vault kv get secret/ti-demo-all/${REGION}/xxxx/${NS}/${IMGSHA}/mysecret1" 2 A03
  test "vault kv get secret/ti-demo-all/xxxx/${CLUSTER}/${NS}/${IMGSHA}/mysecret1" 2 A04
  test "vault kv get secret/ti-demo-all/${REGION}/${CLUSTER}/${NS}/xxxx/mysecret1" 2 A05


  echo "Testing the 'demo' role: "
  export ROLE="demo"
  RESP=$(login ${ROLE})
  export VAULT_TOKEN=$(echo $RESP | jq -r '.auth.client_token')
  REGION=$(echo $RESP | jq -r '.auth.metadata."region"')
  CLNAME=$(echo $RESP | jq -r '.auth.metadata."cluster-name"')
  IMAGES=$(echo $RESP | jq -r '.auth.metadata.images')
  NS=$(echo $RESP | jq -r '.auth.metadata.namespace')

  test "vault kv get secret/ti-demo-all/${REGION}/${CLUSTER}/${NS}/${IMGSHA}/mysecret1" 0 D01
  test "vault kv get secret/ti-demo-all/${REGION}/${CLUSTER}/xxxx/${IMGSHA}/mysecret1" 2 D02
  test "vault kv get secret/ti-demo-all/${REGION}/xxxx/${NS}/${IMGSHA}/mysecret1" 2 D03
  test "vault kv get secret/ti-demo-all/xxxx/${CLUSTER}/${NS}/${IMGSHA}/mysecret1" 2 D04
  test "vault kv get secret/ti-demo-all/${REGION}/${CLUSTER}/${NS}/xxxx/mysecret1" 2 D05

  # testing rule demo-n with policy ti-policy-n
  echo "Testing the 'demo-n' role: "
  export ROLE="demo-n"
  RESP=$(login ${ROLE})
  export VAULT_TOKEN=$(echo $RESP | jq -r '.auth.client_token')
  REGION=$(echo $RESP | jq -r '.auth.metadata."region"')
  CLUSTER=$(echo $RESP | jq -r '.auth.metadata."cluster-name"')
  IMGSHA=$(echo $RESP | jq -r '.auth.metadata.images')
  NS=$(echo $RESP | jq -r '.auth.metadata.namespace')

  test "vault kv get secret/ti-demo-n/${REGION}/${CLUSTER}/${NS}/mysecret3" 0 N01
  test "vault kv get secret/ti-demo-n/${REGION}/${CLUSTER}/xxxx/mysecret3" 2 N02
  test "vault kv get secret/ti-demo-n/${REGION}/xxxx/${NS}/mysecret3" 2 N03
  test "vault kv get secret/ti-demo-n/xxxx/${CLUSTER}/${NS}/${IMGSHA}/mysecret3" 2 N04

  # testing rule demo-r with policy ti-demo-r
  echo "Testing the 'demo-r' role: "
  export ROLE="demo-r"
  RESP=$(login ${ROLE})
  export VAULT_TOKEN=$(echo $RESP | jq -r '.auth.client_token')
  REGION=$(echo $RESP | jq -r '.auth.metadata."region"')

  # testing rule demo-r
  test "vault kv get secret/ti-demo-r/${REGION}/mysecret4" 0 R01
  test "vault kv get secret/ti-demo-r/xxxx/mysecret4" 2 R02
  test "vault kv get secret/ti-demo-r/${REGION}/mysecret5" 0 R03
  test "vault kv get secret/ti-demo-r/${REGION}/test.json" 0 R04
  test "vault kv get secret/ti-demo-r/${REGION}/mysecret2.json" 0 R05

  echo "Testing non-existing role"
  RESP=$(login xxxx_role)
  echo $RESP | grep "role could not be found" > /dev/null
  if [ "$?" == "0" ]; then
    echo "E01 Test successful! RT: 0"
  else
    echo "E01 Test failed: non-existing role NOT detected."
  fi

  echo "Testing access w/o token"
  export VAULT_TOKEN=
  test "vault kv get secret/ti-demo-all/dal01/xxx/xxx/xxx/mysecret1" 2 E02
  test "vault kv get secret/ti-demo-r/dal01/mysecret1" 2 E03

  echo "Make sure to re-run 'setup-vault-cli.sh' as this script overrides the environment values"
} # end of tests

# validate the arguments
if [[ "$VAULT_ADDR" == "" ]] ; then
  echo "VAULT_ADDR must be set"
  helpme
else
  tests
fi
