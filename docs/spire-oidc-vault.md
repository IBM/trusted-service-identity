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
Now we are ready to run the script.
Please make sure the following env. variables are set:
* SPIRE_SERVER
* ROOT_TOKEN
* VAULT_ADDR

or pass them as script parameters:

```console
examples/spire/vault-oidc.sh
# or
examples/spire/vault-oidc.sh <SPIRE_SERVER> <ROOT_TOKEN> <VAULT_ADDR>

```

Now, create a test secret value:
```console
vault kv put secret/my-super-secret test=123
```

## Testing the workload access to Vault secret
Get create a workload and get inside:


apk add jq
# curl --request POST --data @payload.json http://tsi-kube01-9d995c4a8c7c5f281ce13d5467ff6a94-0000.us-south.containers.appdomain.cloud/v1/auth/jwt/login
# export JWT=
# export ROLE=eurole
# export VAULT_ADDR=http://tsi-kube01-9d995c4a8c7c5f281ce13d5467ff6a94-0000.us-south.containers.appdomain.cloud
# SC=$(curl --max-time 10 -s -w "%{http_code}" -o out --request POST --data '{"jwt": "'"${JWT}"'", "role": "'"${ROLE}"'"}' "${VAULT_ADDR}"/v1/auth/jwt/login 2> /dev/null)

TOKEN=$(cat out | jq -r '.auth.client_token')
curl -H "X-Vault-Token: $TOKEN" $VAULT_ADDR/v1/secret/data/my-super-secret
curl -s -H "X-Vault-Token: $TOKEN" $VAULT_ADDR/v1/secret/data/my-super-secret | jq
-r '.data.data'
