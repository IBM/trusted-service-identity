# OIDC Tutorial with Vault
In this tutorial we show how to use SPIRE and OIDC to authenticate workloads to
retrieve Vault secrets.

This tutorial is based on the SPIFFE documentation [("Using SPIRE JWT-SVIDs to Authenticate
to Hashicorp Vault")](https://spiffe.io/docs/latest/keyless/vault/readme/)

This part of the tutorial assumes that OIDC is already [enabled on SPIRE](./spire-oidc-tutorial.md)

## Start a Vault instance:
For the purpose of this tutorial you can start your own instance of Vault
as described [here](https://spiffe.io/docs/latest/keyless/vault/readme/#create-the-config-file-and-run-the-vault-server)
or you can start the simple Vault instance as described in TSI documentation
[Setup Vault](./vault.md)

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

## Configure a Vault instance:
We have a script [examples/spire/vault-oidc.sh](../examples/spire/vault-oidc.sh) that configures the Vault instance with the required demo configuration, but before we run it, let's first explain what happens.

**All the commands listed here are in the script, so don't run them!**

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
vault write auth/jwt/config oidc_discovery_url=$OIDC_URL default_role=“dev”
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
          "sub":"spiffe://openshift.space-x.com/region/*/cluster_name/*/ns/*/sa/elon-musk/pod_name/mars-mission-*"
      },
      "token_ttl": "1h",
      "token_policies": "my-dev-policy"
  }
EOF

vault write auth/jwt/role/marsrole -<role.json
```

We are ready to run the setup script [examples/spire/vault-oidc.sh](../examples/spire/vault-oidc.sh)

Please make sure the following env. variables are set:
* OIDC_URL
* ROOT_TOKEN
* VAULT_ADDR

or pass them as script parameters:

```
examples/spire/vault-oidc.sh
# or
examples/spire/vault-oidc.sh <OIDC_URL> <ROOT_TOKEN> <VAULT_ADDR>

```
Here is our example:
```console
examples/spire/vault-oidc.sh https://oidc-tornjak.space-x01-9d995c4a8c7c5f281ce13d546a94-0000.us-east.containers.appdomain.cloud $ROOT_TOKEN $VAULT_ADDR
```


Once the script successfully completes,
create a test secret value:
```console
vault kv put secret/my-super-secret test=123
```

Put a sample file into Vault:
```console
vault kv put secret/config.json @config.json
```

## Testing the workload access to Vault secret
For testing this setup we are going to use
the test deployment file [examples/spire/mars-demo.yaml](examples/spire/mars-demo.yaml)

This container already has AWS S3 cli, Vault client and the SPIRE agent binaries
for running this experiment.

This example has a following label:

```yaml
template:
  metadata:
    labels:
      identity_template: "true"
```
This label indicates that pod gets its identity in format defined in the
*K8s workload registrar* configuration file
[k8s-workload-registrar-configmap.tpl](../charts/spire/templates/k8s-workload-registrar-configmap.tpl)

The default format is:

```
identity_template = "{{ "region/{{.Context.Region}}/cluster_name/{{.Context.ClusterName}}/ns/{{.Pod.Namespace}}/sa/{{.Pod.ServiceAccount}}/pod_name/{{.Pod.Name}}" }}"
```

Update the `mars-demo` deployment file with the following attributes:
* *VAULT_ADDR* - Vault address as obtained earlier during the Vault setup
* *VAULT_ROLE* - Vault role used during setup
* *VAULT_SECRET* - Secret name and location

Example:
```yaml
- name: VAULT_ADDR
  value: "http://tsi-kube01-9d995c4a8c7c5f281ce13d5467ff6a94-0000.us-south.containers.appdomain.cloud"
- name: VAULT_ROLE
  value: "marsrole"
- name: VAULT_SECRET
  value: "/v1/secret/data/my-super-secret"
```

Let's create a pod and get inside the container:

```console
kubectl -n default create -f examples/spire/mars-demo.yaml

kubectl -n default get po
NAME                           READY   STATUS    RESTARTS   AGE
mars-mission-97745ff46-mmzpb   1/1     Running   0          6h8m

kubectl -n default exec -it mars-mission-97745ff46-mmzpb -- sh
```

Once inside, let's run the [demo-vault.sh](../examples/spire/demo.mars-vault.sh) script
that contains [demoscript](https://github.com/duglin/tools/tree/master/demoscript)
to execute the demo commands. *(Use the space bar to drive the script steps.)*

```
root@ip-192-168-62-164:/usr/local/bin# ./demo-vault.sh

$ /opt/spire/bin/spire-agent api fetch jwt -audience vault -socketPath /run/spire/sockets/agent.sock
```
<<<<<<< HEAD

The JWT token is the long string that follows the **token**:

```console
bin/spire-agent api fetch jwt -audience vault -socketPath /run/spire/sock
ets/agent.sock
token(spiffe://openshift.space-x.com/region/us-east/cluster_name/space-x01/ns/default/sa/elon-musk/pod_name/mars-mission-7874fd667c-rchk5):
	eyJhbGciOiJSUzI1NiIs....cy46fb465a
```

export this long string as JWT env. variable:

=======
This operation retrieves the SPIFFE id for this pod with its JWT representation.
e.g:
>>>>>>> main
```
token(spiffe://openshift.space-x.com/region/us-east-1/cluster_name/aws-tsi-test-03/ns/default/sa/elon-musk/pod_name/mars-mission-f5844b797-br5w9)
. . . .
```
Then we capture the JWT into `token.jwt` file. We use `vault` as audience field.

```
$ /opt/spire/bin/spire-agent api fetch jwt -audience vault -socketPath /run/spire/sockets/agent.sock | sed -n '2p' | xargs > token.jwt
JWT=$(cat token.jwt)
```

Using the captured JWT, we try to login to Vault and get the authentication token for this identity:
```
$ curl --max-time 10 -s -o vout --request POST --data '{"jwt": "${JWT}", "role": "${VAULT_ROLE}" }' http://tsi-kube01-9d995c4a8c7c5f281ce13d5467ff6a94-0000.us-south.containers.appdomain.cloud/v1/auth/jwt/login
$ TOKEN=$(cat vout | jq -r ".auth.client_token")
```

Using this authentication token we request the secret:
```
$ curl -s -H "X-Vault-Token: $TOKEN" http://tsi-kube01-9d995c4a8c7c5f281ce13d5467ff6a94-0000.us-south.containers.appdomain.cloud/v1/secret/data/my-super-secret | jq -r '.data.data'

{
  "test": "123"
}
```
