#!/bin/bash

# Trusted Servie Identiy plugin name
export PLUGIN="vault-plugin-auth-ti-jwt"
# test image name
export IMG="res-kompass-kompass-docker-local.artifactory.swg-devops.com/vault-cli:v0.1"
# export IMGSHA="f36b6d491e0a62cb704aea74d65fabf1f7130832e9f32d0771de1d7c727a79cc"
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
  REGION=$(echo $RESP | jq -r '.auth.metadata."cluster-region"')
  CLNAME=$(echo $RESP | jq -r '.auth.metadata."cluster-name"')
  IMAGES=$(echo $RESP | jq -r '.auth.metadata.images')
  NS=$(echo $RESP | jq -r '.auth.metadata.namespace')


  test "vault kv get secret/ti-demo-all/${REGION}/${CLNAME}/${NS}/${IMAGES}/dummy" 0 A01
  test "vault kv get secret/ti-demo-all/XXX/${CLNAME}/${NS}/${IMAGES}/dummy" 2 A02
  test "vault kv get secret/ti-demo-all/${REGION}/XXX/${NS}/${IMAGES}/dummy" 2 A03
  test "vault kv get secret/ti-demo-all/${REGION}/${CLNAME}/XXX/${IMAGES}/dummy" 2 A04
  test "vault kv get secret/ti-demo-all/${REGION}/${CLNAME}/${NS}/XXX/dummy" 2 A05
  test "vault kv get secret/ti-demo-all/eu-de/${CLNAME}/${NS}/${IMAGES}/dummy" 2 A06
  test "vault kv get secret/ti-demo-all/dal12/${CLNAME}/${NS}/${IMAGES}/dummy" 2 A07
  test "vault kv get secret/ti-demo-all/wdc01/${CLNAME}/${NS}/${IMAGES}/dummy" 0 A08

  test "vault kv get secret/ti-demo-all/eu-de/EUcluster/trusted-identity/${IMGSHA}/dummy" 2 A09
  test "vault kv get secret/ti-demo-r/eu-de/dummy" 2 A10
  test "vault kv get secret/ti-demo-all/eu-de/EUcluster/trusted-identity/${IMGSHA}/dummy" 2 A11
  test "vault kv get secret/ti-demo-all/eu-de/XXcluster/trusted-identity/${IMGSHA}/dummy" 2 A12
  test "vault kv get secret/ti-demo-all/dal01/UScluster/trusted-identity/${IMGSHA}/dummy" 2 A13
  test "vault kv get secret/ti-demo-all/wdc01/UScluster/trusted-identity/${IMGSHA}/dummy" 0 A14

  echo "Testing the 'demo' role: "
  export ROLE="demo"
  RESP=$(login ${ROLE})
  export VAULT_TOKEN=$(echo $RESP | jq -r '.auth.client_token')
  REGION=$(echo $RESP | jq -r '.auth.metadata."cluster-region"')
  CLNAME=$(echo $RESP | jq -r '.auth.metadata."cluster-name"')
  IMAGES=$(echo $RESP | jq -r '.auth.metadata.images')
  NS=$(echo $RESP | jq -r '.auth.metadata.namespace')

  test "vault kv get secret/ti-demo-all/${REGION}/${CLNAME}/${NS}/${IMAGES}/dummy" 0 D01
  test "vault kv get secret/ti-demo-all/XXX/${CLNAME}/${NS}/${IMAGES}/dummy" 2 D02
  test "vault kv get secret/ti-demo-all/${REGION}/XXX/${NS}/${IMAGES}/dummy" 2 D03
  test "vault kv get secret/ti-demo-all/${REGION}/${CLNAME}/XXX/${IMAGES}/dummy" 2 D04
  test "vault kv get secret/ti-demo-all/${REGION}/${CLNAME}/${NS}/XXX/dummy" 2 D05
  test "vault kv get secret/ti-demo-all/eu-de/${CLNAME}/${NS}/${IMAGES}/dummy" 2 D06
  test "vault kv get secret/ti-demo-all/dal12/${CLNAME}/${NS}/${IMAGES}/dummy" 2 D07
  test "vault kv get secret/ti-demo-all/wdc01/${CLNAME}/${NS}/${IMAGES}/dummy" 0 D08

  test "vault kv get secret/ti-demo-all/eu-de/EUcluster/trusted-identity/${IMGSHA}/dummy" 2 D09
  test "vault kv get secret/ti-demo-r/eu-de/dummy" 2  D10
  test "vault kv get secret/ti-demo-all/eu-de/EUcluster/trusted-identity/${IMGSHA}/dummy" 2 D11
  test "vault kv get secret/ti-demo-all/eu-de/XXcluster/trusted-identity/${IMGSHA}/dummy" 2 D12
  test "vault kv get secret/ti-demo-all/dal01/UScluster/trusted-identity/${IMGSHA}/dummy" 2 D13
  test "vault kv get secret/ti-demo-all/wdc01/UScluster/trusted-identity/${IMGSHA}/dummy" 0 D14
  test "vault kv get secret/ti-demo-r/${REGION}/dummy" 2 D15
  test "vault kv get secret/ti-demo-n/${REGION}/${CLNAME}/${NS}/dummy" 2 D16


  # testing rule demo-n with policy ti-policy-n
  echo "Testing the 'demo-n' role: "
  export ROLE="demo-n"
  RESP=$(login ${ROLE})
  export VAULT_TOKEN=$(echo $RESP | jq -r '.auth.client_token')
  REGION=$(echo $RESP | jq -r '.auth.metadata."cluster-region"')
  CLNAME=$(echo $RESP | jq -r '.auth.metadata."cluster-name"')
  IMAGES=$(echo $RESP | jq -r '.auth.metadata.images')
  NS=$(echo $RESP | jq -r '.auth.metadata.namespace')

  test "vault kv get secret/ti-demo-all/${REGION}/${CLNAME}/${NS}/${IMAGES}/dummy" 2 N01
  test "vault kv get secret/ti-demo-n/${REGION}/${CLNAME}/${NS}/dummy" 0 N02
  test "vault kv get secret/ti-demo-n/XXX/${CLNAME}/${NS}/dummy" 2 N03
  test "vault kv get secret/ti-demo-n/${REGION}/XXX/${NS}/dummy" 2 N04
  test "vault kv get secret/ti-demo-n/${REGION}/${CLNAME}/XXX/dummy" 2 N05
  test "vault kv get secret/ti-demo-n/eu-de/EUcluster/trusted-identity/dummy" 2 N06
  test "vault kv get secret/ti-demo-n/eu-de/XXcluster/trusted-identity/dummy" 2 N07
  test "vault kv get secret/ti-demo-n/dal01/UScluster/trusted-identity/dummy" 2 N08
  test "vault kv get secret/ti-demo-n/wdc01/UScluster/trusted-identity/dummy" 0 N09
  test "vault kv get secret/ti-demo-r/${REGION}/dummy" 2 N10



  # testing rule demo-r with policy ti-demo-r
  echo "Testing the 'demo-r' role: "
  export ROLE="demo-r"
  RESP=$(login ${ROLE})
  export VAULT_TOKEN=$(echo $RESP | jq -r '.auth.client_token')
  REGION=$(echo $RESP | jq -r '.auth.metadata."cluster-region"')

  # # for testing rule demo-r
  test "vault kv get secret/ti-demo-all/${REGION}/${CLNAME}/${NS}/${IMAGES}/dummy" 2 R01
  test "vault kv get secret/ti-demo-r/${REGION}/dummy" 0 R02
  test "vault kv get secret/ti-demo-r/eu-de/dummy" 2 R03
  test "vault kv get secret/ti-demo-r/dal01/dummy" 2 R04
  test "vault kv get secret/ti-demo-r/wdc01/dummy" 0 R05
  test "vault kv get secret/ti-demo-n/${REGION}/${CLNAME}/${NS}/dummy" 2 R06


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
  test "vault kv get secret/ti-demo-all/dal01/xxx/xxx/xxx/dummy" 2 E02
  test "vault kv get secret/ti-demo-r/dal01/dummy" 2 E03

  echo "Make sure to re-run 'setup-vault-cli.sh' as this script overrides the environment values"
  }

# validate the arguments
if [[ "$VAULT_ADDR" == "" ]] ; then
  echo "VAULT_ADDR must be set"
  helpme
else
  tests
fi
