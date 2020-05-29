#!/bin/bash

# Trusted Service Identiy plugin name
export PLUGIN="vault-plugin-auth-ti-jwt"
# test image names
# VIMG - Vault Client image, UIMG - myubuntu image
export VIMG="trustedseriviceidentity/vault-cli:v0.3"
export UIMG="ubuntu@sha256:250cc6f3f3ffc5cdaa9d8f4946ac79821aafb4d3afc93928f0de9336eba21aa4"
getSHA()
{
# sha-256 encoded file name based on the OS:
if [[ "$OSTYPE" == "linux-gnu" ]]; then
  # Linux
  VIMGSHA=$(echo -n "$VIMG" | sha256sum | awk '{print $1}')
  UIMGSHA=$(echo -n "$UIMG" | sha256sum | awk '{print $1}')
elif [[ "$OSTYPE" == "darwin"* ]]; then
  # Mac OSX
  VIMGSHA=$(echo -n "$VIMG" | shasum -a 256 | awk '{print $1}')
  UIMGSHA=$(echo -n "$UIMG" | shasum -a 256 | awk '{print $1}')
else
  # Unknown.
  echo "Unsupported plaftorm to execute this test. Set the IMGSHA environment"
  echo "variable to represent sha 256 encoded name of the test image"
  exit 1
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
   $0 [region] [cluster] [namespace] [full image name (optional)]

where:
      [region]: eu-de, us-south, eu-gb, ...
      [cluster]: cluster name
      [namespace]: namespace of the application container
      [full image name (optional)]: e.g. trustedseriviceidentity/vault-cli:v0.3

HELPMEHELPME
}

loadVault()
{
  if [[ "$VIMGSHA" == "" || "$UIMGSHA" == "" ]]; then
    return 1
  fi

  #docker run -d --name=dev-vault -v ${PWD}/local.json:/vault/config/local.json -v ${PWD}/pkg/linux_amd64/${PLUGIN}:/plugins/${PLUGIN} -p 127.0.0.1:8200:8200/tcp vault
  # echo "Root Token: ${ROOT_TOKEN}"
  vault login -no-print ${ROOT_TOKEN}
  RT=$?
  if [ $RT -ne 0 ] ; then
     echo "ROOT_TOKEN is not correctly set"
     echo "ROOT_TOKEN=${ROOT_TOKEN}"
     exit 1
  fi

  # write policy to grant access to secrets
  vault policy read tsi-policy-rcni
  RT=$?
  if [ $RT -ne 0 ] ; then
     echo "vault tsi-policy-rcni policy does not exist. Did you load the policies?"
     exit 1
  fi

  vault read auth/trusted-identity/role/tsi-role-rcni
  RT=$?
  if [ $RT -ne 0 ] ; then
     echo "vault auth/trusted-identity/role/tsi-role-rcni policy does not exist. Did you load the policies?"
     exit 1
  fi


  # # write some data to be read later on
  # # testing role `tsi-role-rcni` with tsi-policy-rcni
  vault kv put secret/tsi-rcni/${REGION}/${CLUSTER}/${NAMESPACE}/${VIMGSHA}/mysecret1 all=good
  vault kv get secret/tsi-rcni/${REGION}/${CLUSTER}/${NAMESPACE}/${VIMGSHA}/mysecret1
  vault kv put secret/tsi-rcni/${REGION}/${CLUSTER}/${NAMESPACE}/${UIMGSHA}/mysecret1 secret=very5ecret!value
  vault kv get secret/tsi-rcni/${REGION}/${CLUSTER}/${NAMESPACE}/${UIMGSHA}/mysecret1

  # ${NAMESPACE}ing rule tsi-role-rcn with policy tsi-policy-rcn
  vault kv put secret/tsi-rcn/${REGION}/${CLUSTER}/${NAMESPACE}/mysecret3 mysecret=my5ecret@1
  vault kv get secret/tsi-rcn/${REGION}/${CLUSTER}/${NAMESPACE}/mysecret3

  # testing role tsi-role-r with policy tsi-r
  vault kv put secret/tsi-r/${REGION}/mysecret4 secret=An0ther5ecret!now
  vault kv get secret/tsi-r/${REGION}/mysecret4

  # pass JSON as a value:
  echo -n '{"value1":"itsasecret", "value2":"itsabigsecret"}' | vault kv put  secret/tsi-r/${REGION}/mysecret5 -
  vault kv get secret/tsi-r/${REGION}/mysecret5

  # tsi-role-rcninstrate passing a JSON file as value
  cat >./test.json <<EOF
  {
      "apiVersion": "v1",
      "kind": "Service",
      "metadata": {
          "creationTimestamp": "2019-05-02T15:24:32Z",
          "name": "ti-vault",
          "namespace": "test",
          "resourceVersion": "1078959",
          "selfLink": "/api/v1/namespaces/test/services/ti-vault",
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

  vault kv put secret/tsi-r/${REGION}/test.json @test.json
  vault kv get secret/tsi-r/${REGION}/test.json
  vault kv put secret/tsi-r/${REGION}/mysecret2.json @test.json
  vault kv get secret/tsi-r/${REGION}/mysecret2.json
  }

# validate the arguments
if [[ "$ROOT_TOKEN" == "" || "$VAULT_ADDR" == "" ]] ; then
  echo "ROOT_TOKEN and VAULT_ADDR enviroment variables must be set"
  helpme
elif [[ "$1" == "-?" || "$1" == "-h" || "$1" == "--help" || "$3" == "" ]] ; then
    helpme
else
  REGION=$1
  CLUSTER=$2
  NAMESPACE=$3

  if  [[ "$4" != "" ]] ; then
    IMG=$4
  fi
  getSHA
  loadVault
fi
