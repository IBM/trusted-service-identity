# Trusted Service Identity Application Developer - using Vault Plugin
This document guides through adapting your application to be used with Trusted
Service Identity with a Vault.

Before starting to integrate your application with TIS, please make sure to run
the [Demo with Vault Plugin](./vault/README.md) first.

Demo components:
* [vault](./vault) - authentication plugin extension to Hashicorp Vault
* [vault-client](./vault-client) - sample client that demonstrates how to retrieve
secrets from Vault

## Assumptions
We assume that at this point you have a working K8s cluster with Trusted Service Identity
environment deployed, including the sample Vault server and client.
Otherwise, please see [vault/README.md](./vault/README.md)

There are two roles needed to continue:
* Vault admin - the person who has privileges to access and change entries in Vault
(ROOT_TOKEN and VAULT_ADDR env. needed)
* application cluster owner - the person with access to the cluster (KUBECONFIG)

## Test sample Vault client
If the demo was successfully executed, there should be a Vault server ('tsi-vault')
and client (`vault-cli`) running.
Open a new console and exec into the vault client container as an application
cluster owner:

```
alias k="kubectl -n trusted-identity"
k exec -it $(k get po | grep vault-cli | awk '{print $1}') /bin/bash
```
By default JWT Tokens are created every 30 seconds and they are available in `/jwt-tokens`
directory. One can inspect the content of the token by simply pasting it into
[Debugger](https://jwt.io/) in Encoded window.
Sample Payload:

```json
{
  "cluster-name": "ti_demo",
  "cluster-region": "dal09",
  "exp": 1557170306,
  "iat": 1557170276,
  "images": "f36b6d491e0a62cb704aea74d65fabf1f7130832e9f32d0771de1d7c727a79cc",
  "images-names": "trustedseriviceidentity/myubuntu@sha256:5b224e11f0e8daf35deb9aebc86218f1c444d2b88f89c57420a61b1b3c24584c",
  "iss": "wsched@us.ibm.com",
  "machineid": "fa967df1a948495596ad6ba5f665f340",
  "namespace": "trusted-identity",
  "pod": "vault-cli-84c8d647c-s6cgb",
  "sub": "wsched@us.ibm.com"
}
```

Source the `setup-vault-cli.sh` script to setup Vault token. Then try to login
with the default `demo` policy role:

```console
source ./setup-vault-cli.sh
curl --request POST --data '{"jwt": "'"${TOKEN}"'", "role": "demo"}' ${VAULT_ADDR}/v1/auth/trusted-identity/login | jq
```
This will return the data associated with this application for the specified role ('demo')
```json
{
  "request_id": "fec49645-04db-f1ff-82e2-147d276acc3d",
  "lease_id": "",
  "renewable": false,
  "lease_duration": 0,
  "data": null,
  "wrap_info": null,
  "warnings": null,
  "auth": {
    "client_token": "s.N1DvJruie10GpclrjuhZZfWV",
    "accessor": "bQTiSsN09HQ0QvFxbZgApqVn",
    "policies": [
      "default",
      "ti-policy-all"
    ],
    "token_policies": [
      "default",
      "ti-policy-all"
    ],
    "metadata": {
      "cluster-name": "ti_demo",
      "cluster-region": "dal09",
      "images": "f36b6d491e0a62cb704aea74d65fabf1f7130832e9f32d0771de1d7c727a79cc",
      "namespace": "trusted-identity",
      "role": "demo"
    },
    "lease_duration": 2764800,
    "renewable": true,
    "entity_id": "5d6d6eab-58c6-75e3-bdb4-c0eb92dab06f",
    "token_type": "service"
  }
}
```

## Create Policies (Vault admin)
Make sure to become Vault admin (see the [demo](./vault/README.md))

There are few sample policies available in `vault/ti.policy.X.hcl.tpl`.
They have following constraints:
* all - uses cluster-region, cluster-name, namespace and images
* n - uses cluster-region, cluster-name and namespace
* r - uses cluster-region only

If you need to change them, modify templates and re-run  [vault/demo.load-sample-policies.sh](./vault/demo.load-sample-policies.sh) script.


## Create Secrets
Using the values obtained from the claims you can build new secrets. See the
[vault/demo.load-sample-keys.sh](vault/demo.load-sample-keys.sh)
script to create sample keys.

Using claims above as example, define the following variables:

```console
export REGION="dal09"
export CLUSTER="ti_demo"
export IMGSHA="f36b6d491e0a62cb704aea74d65fabf1f7130832e9f32d0771de1d7c727a79cc"
export NAMESPACE="trusted-identity"
```

To obtain obtain the SHA for any image name, do following:
```console
export IMG="trustedseriviceidentity/vault-cli:v0.3"

# on Mac:
IMGSHA=$(echo -n "$IMG" | shasum -a 256 | awk '{print $1}')
# on Linux:
IMGSHA=$(echo -n "$IMG" | sha256sum | awk '{print $1}')

echo $IMGSHA
```

As an example, let's create a secret that is only available to the application that
runs in region labeled as "dal09", cluster named "ti_demo", namespace "trusted-identity"
and the image name SHA="f36b6d491e0a62cb704aea74d65fabf1f7130832e9f32d0771de1d7c727a79cc".
We will be using a policy `demo-all` that has the following constraints:
* region
* cluster-name
* namespace
* imageSHA

```console
vault kv put secret/ti-demo-all/${REGION}/${CLUSTER}/${NAMESPACE}/${IMGSHA}/password value=mysecret
vault kv get secret/ti-demo-all/${REGION}/${CLUSTER}/${NAMESPACE}/${IMGSHA}/password
```

For policy that uses only one constraint, region (demo-r):
```console
vault kv put secret/ti-demo-r/${REGION}/password value=mysecret2
vault kv get secret/ti-demo-r/${REGION}/password
```

And so on.

To pass JSON as a value:
```console
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
```


## Retrieve keys in the Vault client
Once the keys are provided you should be able to read them from the Vault client.
To read `secret/ti-demo-all/${REGION}/${CLUSTER}/${NAMESPACE}/${IMGSHA}/password`
with a role `demo-all`:

```console
export TOKEN=$(cat /jwt-tokens/token)
export RESP=$(curl --request POST --data '{"jwt": "'"${TOKEN}"'", "role": "'"${ROLE}"'"}' ${VAULT_ADDR}/v1/auth/trusted-identity/login 2> /dev/null)
export VAULT_TOKEN=$(echo $RESP | jq -r '.auth.client_token')

# double-quotes required when the key name contains '-'
REGION=$(echo $RESP | jq -r '.auth.metadata."cluster-region"')
CLUSTER=$(echo $RESP | jq -r '.auth.metadata."cluster-name"')
IMGSHA=$(echo $RESP | jq -r '.auth.metadata.images')
NS=$(echo $RESP | jq -r '.auth.metadata.namespace')

# execute retrieve:
vault kv get secret/ti-demo-all/${REGION}/${CLUSTER}/${NS}/${IMGSHA}/password

```
