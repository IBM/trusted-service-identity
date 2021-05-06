# OIDC Tutorial with Vault
In this tutorial we show how to use SPIRE and OIDC to authenticate workloads to
retrieve Vault secrets.

This tutorial is based on the documentation for [Using SPIRE JWT-SVIDs to Authenticate
to Hashicorp Vault](https://spiffe.io/docs/latest/keyless/vault/readme/)

This part of the tutorial assumes that OIDC is already [enabled on SPIRE](./spire-oidc-tutorial.md)

## Start a Vault instance:
For the purpose of this tutorial you can start your own instance of Vault
as described [here](https://spiffe.io/docs/latest/keyless/vault/readme/#create-the-config-file-and-run-the-vault-server)
or you can start the simple Vault instance as described in TSI documentation
[Setup Vault](../README.md#setup-vault)

Obtain the **VAULT_ADDR** and **ROOT_TOKEN** as documented. (ROOT_TOKEN is displayed
in the log file)

```console
export VAULT_ADDR=http://<Ingress_or_external_route>
export ROOT_TOKEN=$(kubectl -n tsi-vault logs $(kubectl -n tsi-vault get po | grep tsi-vault-| awk '{print $1}') | grep Root | cut -d' ' -f3); echo "export ROOT_TOKEN=$ROOT_TOKEN"
```

Now test the connection to Vault:
```console
vault login -no-print "${ROOT_TOKEN}"
```

## Configure a Vault instace:
We have a script [examples/spire/vault-oidc.sh](examples/spire/vault-oidc.sh) that configures the Vault instance with the required demo configuration, but before we run it, let's first explain what happens.

First few commands enable the Secret Engine and setup Vault OIDC Federation with
our instance of SPIRE.

```
# Enable the kv (key-value) secrets engine on the secret/ path:
vault secrets enable -path=secret kv

# Enable the JWT authentication method:
vault auth enable jwt
```

Set up our OIDC Discovery URL, using the values created in [OIDC tutorial setup](./spire-oidc-tutorial.md)
and using defalt role **dev**:
```
vault write auth/jwt/config oidc_discovery_url=$SPIRE_SERVER default_role=“dev”
```

Define a policy `my-dev-policy` that gives `read` access to `my-super-secret`:
```console
cat > vault-policy.hcl <<EOF
path "secret/data/my-super-secret" {
   capabilities = ["read"]
}
EOF

# create this policy:
vault policy write my-dev-policy ./vault-policy.hcl
```
Create `eurole` role that allows 1h access to the above policy only to applications
running in EU region (eu-*), in any cluster, in any namespace, under `elon-musk`
service account and `mars-mission-main` container.

`bound_subject` does not allow using wildcards, so we use `bound_claims` instead:
```console
cat > role.json <<EOF
  {
      "role_type":"jwt",
      "user_claim": "sub",
      "bound_audiences": "vault",
      "bound_claims_type": "glob",
      "bound_claims": {
          "sub":"spiffe://openshift.space-x.com/eu-*/*/*/elon-musk/mars-mission-main/*"
      },
      "token_ttl": "1h",
      "token_policies": "my-dev-policy"
  }
EOF

vault write auth/jwt/role/eurole -<role.json
```

We are ready to run the setup script.
Please make sure the following env. variables are set:
* OIDC_URL
* ROOT_TOKEN
* VAULT_ADDR

or pass them as script parameters:

```console
examples/spire/vault-oidc.sh
# or
examples/spire/vault-oidc.sh <OIDC_URL> <ROOT_TOKEN> <VAULT_ADDR>

```

Now, create a test secret value:
```console
vault kv put secret/my-super-secret test=123
```

## Testing the workload access to Vault secret
For testing this setup we are going to use
[examples/spire/mars-spaceX.yaml](examples/spire/mars-spaceX.yaml) deployment.

Based on the following annotation:

```yaml

metadata:
  annotations:
    spire-workload-id: eu-de/space-x.01/default/elon-musk/mars-mission-main/c0d076b51c28dc937a70a469b4cc946fb465ab6c86d6ae89ae2cf8eac1f55d6b

```
this container will get the following identity:

`eu-de/space-x.01/default/elon-musk/mars-mission-main/c0d076b51c28dc937a70a469b4cc946fb465ab6c86d6ae89ae2cf8eac1f55d6b`

Let's create a container and get inside:

```console
kubectl -n default create -f examples/spire/mars-spaceX.yaml

kubectl -n default get po
NAME                           READY   STATUS    RESTARTS   AGE
mars-mission-97745ff46-mmzpb   1/1     Running   0          6h8m

kubectl -n default exec -it mars-mission-97745ff46-mmzpb -- sh
```

We will need a jq parser, so let's install it here:

```console
apk add jq

```

Now, let's get the identity token from SPIRE agent in form of JWT, using `vault` as audience:

```console
bin/spire-agent api fetch jwt -audience vault -socketPath /run/spire/sockets/agent.sock
```

The JWT token is the long string that follows the **token**:

```console
bin/spire-agent api fetch jwt -audience vault -socketPath /run/spire/sock
ets/agent.sock
token(spiffe://openshift.space-x.com/eu-de/space-x.01/default/elon-musk/mars-mission-main/c0d076b51c28dc937a70a469b4cc946fb465ab6c86d6ae89ae2cf8eac1f55d6b):
	eyJhbGciOiJSUzI1NiIs....cy46fb465a
```

export this long string as JWT env. variable:

```
export JWT=eyJhbGciOiJSUzI1NiIs....cy46fb465a
```
Export also `eurole` as **ROLE** and actual **VAULT_ADDR**

```console
export ROLE=eurole
export VAULT_ADDR=http://tsi-kube01-9d995c4a8c7c5f281ce13d5467ff6a94-0000.us-south.containers.appdomain.cloud
```
Now let's try to login to Vault using the JWT token:

```console
curl --max-time 10 -s -o out --request POST --data '{"jwt": "'"${JWT}"'", "role": "'"${ROLE}"'"}' "${VAULT_ADDR}"/v1/auth/jwt/login
```

If the login was successful, we will get back a response from Vault that ends up in **out** file and might look like this:

```json
cat out |jq
{
 "request_id": "248249fe-0cc5-57e9-6510-ea0999bb916e",
 "lease_id": "",
 "renewable": false,
 "lease_duration": 0,
 "data": null,
 "wrap_info": null,
 "warnings": null,
 "auth": {
   "client_token": "s.v5V8pS6B0ZepwrP2azFxSaA7",
   "accessor": "G2QIZQ7R9YX1Smebmtp9NzH2",
   "policies": [
     "default",
     "my-dev-policy"
   ],
   "token_policies": [
     "default",
     "my-dev-policy"
   ],
   "metadata": {
     "role": "eurole"
   },
   "lease_duration": 86400,
   "renewable": true,
   "entity_id": "d1f13141-079f-0f04-0aa9-4468fd0f93ca",
   "token_type": "service",
   "orphan": true
 }
}
```
what we need is the `client_token` value. Let's get it by parsing the JSON output with **jq**:

```console
TOKEN=$(cat out | jq -r '.auth.client_token')
echo $TOKEN
```
Now we can request the secret, using this token:
```console
curl -s -H "X-Vault-Token: $TOKEN" $VAULT_ADDR/v1/secret/data/my-super-secret | jq -r '.data.data'

{
  "test": "123"
}
```
