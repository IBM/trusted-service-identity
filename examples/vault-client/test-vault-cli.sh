#!/bin/bash

# Trusted Servie Identiy plugin name
export PLUGIN="vault-plugin-auth-ti-jwt"
# test image name
export IMG="tsidentity/vault-cli:v0.3"
# export IMGSHA="f36b6d491e0a62cb704aea74d65fabf1f7130832e9f32d0771de1d7c727a79cc"
JWTFILE="/jwt-tokens/token"

# make sure that JWT file exists
if [ ! -s "$JWTFILE" ]; then
   echo "$JWTFILE does not exist. Make sure Trusted Identity is setup correctly"
   exit 1
fi

# sha-256 encoded file name based on the OS:
if [[ "$OSTYPE" == "linux-gnu" ]]; then
  # Linux
  IMGSHA=$(echo -n "$IMG" | sha256sum | awk '{print $1}')
elif [[ "$OSTYPE" == "darwin"* ]]; then
  # Mac OSX
  IMGSHA=$(echo -n "$IMG" | shasum -a 256 | awk '{print $1}')
else
  # Unknown.
  echo "Unsupported plaftorm to execute this test. Set the IMGSHA environment"
  echo "variable to represent sha 256 encoded name of the test image"
fi

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
local RT=$?
if [ "$RT" == "0" ]; then
     echo $RESP
else
  echo "Login with role $ROLE failed. RT:$RT $RESP"
  echo ""
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
  if [[ "$IMGSHA" == "" ]]; then
    return 1
  fi

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


  test "vault kv get secret/tsi-rcni/${REGION}/${CLUSTER}/${NS}/${IMGSHA}/dummy" 0 A01
  test "vault kv get secret/tsi-rcni/${REGION}/${CLUSTER}/xxxx/${IMGSHA}/dummy" 2 A02
  test "vault kv get secret/tsi-rcni/${REGION}/xxxx/${NS}/${IMGSHA}/dummy" 2 A03
  test "vault kv get secret/tsi-rcni/xxxx/${CLUSTER}/${NS}/${IMGSHA}/dummy" 2 A04
  test "vault kv get secret/tsi-rcni/${REGION}/${CLUSTER}/${NS}/xxxx/dummy" 2 A05


  echo "Testing the 'tsi-role-rcni' role: "
  export ROLE="tsi-role-rcni"
  RESP=$(login ${ROLE})
  export VAULT_TOKEN=$(echo $RESP | jq -r '.auth.client_token')
  REGION=$(echo $RESP | jq -r '.auth.metadata."region"')
  CLNAME=$(echo $RESP | jq -r '.auth.metadata."cluster-name"')
  IMAGES=$(echo $RESP | jq -r '.auth.metadata.images')
  NS=$(echo $RESP | jq -r '.auth.metadata.namespace')

  test "vault kv get secret/tsi-rcni/${REGION}/${CLUSTER}/${NS}/${IMGSHA}/dummy" 0 D01
  test "vault kv get secret/tsi-rcni/${REGION}/${CLUSTER}/xxxx/${IMGSHA}/dummy" 2 D02
  test "vault kv get secret/tsi-rcni/${REGION}/xxxx/${NS}/${IMGSHA}/dummy" 2 D03
  test "vault kv get secret/tsi-rcni/xxxx/${CLUSTER}/${NS}/${IMGSHA}/dummy" 2 D04
  test "vault kv get secret/tsi-rcni/${REGION}/${CLUSTER}/${NS}/xxxx/dummy" 2 D05

  # testing role tsi-role-rcn with policy tsi-policy-rcn
  echo "Testing the 'tsi-role-rcn' role: "
  export ROLE="tsi-role-rcn"
  RESP=$(login ${ROLE})
  export VAULT_TOKEN=$(echo $RESP | jq -r '.auth.client_token')
  REGION=$(echo $RESP | jq -r '.auth.metadata."region"')
  CLUSTER=$(echo $RESP | jq -r '.auth.metadata."cluster-name"')
  IMGSHA=$(echo $RESP | jq -r '.auth.metadata.images')
  NS=$(echo $RESP | jq -r '.auth.metadata.namespace')

  test "vault kv get secret/tsi-rcn/${REGION}/${CLUSTER}/${NS}/dummy" 0 N01
  test "vault kv get secret/tsi-rcn/${REGION}/${CLUSTER}/xxxx/dummy" 2 N02
  test "vault kv get secret/tsi-rcn/${REGION}/xxxx/${NS}/dummy" 2 N03
  test "vault kv get secret/tsi-rcn/xxxx/${CLUSTER}/${NS}/${IMGSHA}/dummy" 2 N04

  # testing role tsi-role-r with policy tsi-r
  echo "Testing the 'tsi-role-r' role: "
  export ROLE="tsi-role-r"
  RESP=$(login ${ROLE})
  export VAULT_TOKEN=$(echo $RESP | jq -r '.auth.client_token')
  REGION=$(echo $RESP | jq -r '.auth.metadata."region"')

  # testing role tsi-role-r
  test "vault kv get secret/tsi-r/${REGION}/dummy" 0 R01
  test "vault kv get secret/tsi-r/xxxx/dummy" 2 R02
  test "vault kv get secret/tsi-r/${REGION}/password" 0 R03
  test "vault kv get secret/tsi-r/${REGION}/test.json" 0 R04

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
  test "vault kv get secret/tsi-rcni/us-south/xxx/xxx/xxx/dummy" 2 E02
  test "vault kv get secret/tsi-r/us-south/dummy" 2 E03

  echo "Make sure to re-run 'setup-vault-cli.sh' as this script overrides the environment values"
  }

# validate the arguments
if [[ "$VAULT_ADDR" == "" ]] ; then
  echo "VAULT_ADDR must be set"
  helpme
else
  tests
fi
