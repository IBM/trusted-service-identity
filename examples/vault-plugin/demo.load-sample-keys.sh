#!/bin/bash

# Trusted Service Identiy plugin name
export PLUGIN="vault-plugin-auth-ti-jwt"
# test image name
export IMG="res-kompass-kompass-docker-local.artifactory.swg-devops.com/vault-cli:v0.3"
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
      -full image name (optional) e.g. res-kompass-kompass-docker-local.artifactory.swg-devops.com/vault-cli:v0.3

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
  vault kv get secret/ti-demo-all/${REGION}/${CLUSTER}/trusted-identity/${IMGSHA}/dummy

  # testing rule demo-n with policy ti-policy-n
  vault kv put secret/ti-demo-n/${REGION}/${CLUSTER}/trusted-identity/dummy policy-n=good
  vault kv get secret/ti-demo-n/${REGION}/${CLUSTER}/trusted-identity/dummy

  # testing rule demo-r with policy ti-demo-r
  vault kv put secret/ti-demo-r/${REGION}/dummy region=good
  vault kv get secret/ti-demo-r/${REGION}/dummy

  # pass JSON as a value:
  echo -n '{"value1":"itsasecret", "value2":"itsabigsecret"}' | vault kv put  secret/ti-demo-r/${REGION}/password -
  vault kv get secret/ti-demo-r/${REGION}/password

  # demonstrate passing a JSON file as value
  cat >./test.json <<EOF
  {
      "apiVersion": "v1",
      "kind": "Service",
      "metadata": {
          "creationTimestamp": "2019-05-02T15:24:32Z",
          "name": "ti-vault",
          "namespace": "trusted-identity",
          "resourceVersion": "1078959",
          "selfLink": "/api/v1/namespaces/trusted-identity/services/ti-vault",
          "uid": "627b7e94-6cee-11e9-9e35-fafb83f6879f"
      },
      "spec": {
          "externalTrafficPolicy": "Cluster",
          "ports": [
              {
                  "nodePort": 32125,
                  "port": 8200,
                  "protocol": "TCP",
                  "targetPort": 8200
              }
          ],
          "selector": {
              "app": "ti-vault"
          },
          "sessionAffinity": "None",
          "type": "NodePort"
      },
      "status": {
          "loadBalancer": {}
      }
  }
EOF

  vault kv put secret/ti-demo-r/${REGION}/test.json @test.json
  vault kv get secret/ti-demo-r/${REGION}/test.json
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
