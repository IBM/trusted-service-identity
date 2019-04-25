#!/bin/bash

# Trusted Servie Identiy plugin name
export PLUGIN="vault-plugin-auth-ti-jwt"
# test image name
export IMG="res-kompass-kompass-docker-local.artifactory.swg-devops.com/vault-cli:v0.1"
# export IMGSHA="f36b6d491e0a62cb704aea74d65fabf1f7130832e9f32d0771de1d7c727a79cc"

getSHA()
{
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
}

## create help menu:
helpme()
{
  cat <<HELPMEHELPME
Make sure ROOT_TOKEN and VAULT_ADDR environment variables are set.
export ROOT_TOKEN=
export VAULT_ADDR=(vault address in format http://vault.server:8200)

syntax:
   $0 [region] [cluster] [full image name (optional)]

where:
      -region: eu-de, dal01, wdc01, ...
      -cluster: cluster name
      -full image name (optional) e.g. res-kompass-kompass-docker-local.artifactory.swg-devops.com/vault-cli:v0.1

HELPMEHELPME
}

loadVault()
{
  if [[ "$IMGSHA" == "" ]]; then
    return 1
  fi

  #docker run -d --name=dev-vault -v ${PWD}/local.json:/vault/config/local.json -v ${PWD}/pkg/linux_amd64/${PLUGIN}:/plugins/${PLUGIN} -p 127.0.0.1:8200:8200/tcp vault
  echo "Root Token: ${ROOT_TOKEN}"
  vault login ${ROOT_TOKEN}
  RT=$?
  if [ $RT -ne 0 ] ; then
     echo "ROOT_TOKEN is not correctly set"
     echo "ROOT_TOKEN=${ROOT_TOKEN}"
     exit 1
  fi

  # write policy to grant access to secrets
  vault policy read ti-policy-all
  RT=$?
  if [ $RT -ne 0 ] ; then
     echo "vault ti-policy-all policy does not exist. Did you load the policies?"
     exit 1
  fi

  vault read auth/trusted-identity/role/demo
  RT=$?
  if [ $RT -ne 0 ] ; then
     echo "vault auth/trusted-identity/role/demo policy does not exist. Did you load the policies?"
     exit 1
  fi


  # # write some data to be read later on
  # # testing rule `demo` with ti-policy-all
  vault kv put secret/ti-demo-all/${REGION}/${CLUSTER}/trusted-identity/${IMGSHA}/dummy all=good
  vault kv put secret/ti-demo-all/${REGION}/${CLUSTER}/xxxx/${IMGSHA}/dummy all=xxxxNamespace
  vault kv put secret/ti-demo-all/${REGION}/xxxx/trusted-identity/${IMGSHA}/dummy all=xxxCluster
  vault kv put secret/ti-demo-all/xxxx/${CLUSTER}/trusted-identity/${IMGSHA}/dummy all=xxxxRegion
  vault kv put secret/ti-demo-all/${REGION}/${CLUSTER}/trusted-identity/xxxx/dummy all=xxxImage

  vault kv get secret/ti-demo-all/${REGION}/${CLUSTER}/trusted-identity/${IMGSHA}/dummy
  vault kv get secret/ti-demo-all/${REGION}/${CLUSTER}/xxxx/${IMGSHA}/dummy
  vault kv get secret/ti-demo-all/${REGION}/xxxx/trusted-identity/${IMGSHA}/dummy
  vault kv get secret/ti-demo-all/xxxx/${CLUSTER}/trusted-identity/${IMGSHA}/dummy
  vault kv get secret/ti-demo-all/${REGION}/${CLUSTER}/trusted-identity/xxxx/dummy

  # testing rule demo-n with policy ti-policy-n
  vault kv put secret/ti-demo-n/${REGION}/${CLUSTER}/trusted-identity/dummy policy-n=good
  vault kv put secret/ti-demo-n/${REGION}/${CLUSTER}/xxxx/dummy policy-n=xxxxNamespace
  vault kv put secret/ti-demo-n/${REGION}/xxxx/trusted-identity/dummy policy-n=xxxCluster
  vault kv put secret/ti-demo-n/xxxx/${CLUSTER}/trusted-identity/dummy policy-n=xxxxRegion

  vault kv get secret/ti-demo-n/${REGION}/${CLUSTER}/trusted-identity/dummy
  vault kv get secret/ti-demo-n/${REGION}/${CLUSTER}/xxxx/dummy
  vault kv get secret/ti-demo-n/${REGION}/xxxx/trusted-identity/dummy
  vault kv get secret/ti-demo-n/xxxx/${CLUSTER}/trusted-identity/dummy

  # testing rule demo-r with policy ti-demo-r
  vault kv put secret/ti-demo-r/${REGION}/dummy region=good
  vault kv put secret/ti-demo-r/xxxx/dummy region=xxxxRegion

  vault kv get secret/ti-demo-r/${REGION}/dummy
  vault kv get secret/ti-demo-r/xxxx/dummy
  }

# validate the arguments
if [[ "$ROOT_TOKEN" == "" || "$VAULT_ADDR" == "" ]] ; then
  echo "ROOT_TOKEN and VAULT_ADDR enviroment variables must be set"
  helpme
elif [[ "$1" == "-?" || "$1" == "-h" || "$1" == "--help" || "$2" == "" ]] ; then
    helpme
else
  REGION=$1
  CLUSTER=$2

  if  [[ "$3" != "" ]] ; then
    IMG=$3
  fi
  getSHA
  loadVault
fi
