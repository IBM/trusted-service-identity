# OIDC Tutorial
This tutorial shows steps how to deploy and enable the OIDC Discovery Provider Service
Once the OIDC is enabled, we can set up workload access to [AWS S3 storage](./spire-oidc-aws-s3.md)
or [Vault secrets](./spire-oidc-vault.md).

In this example we will deploy Tornjak and SPIRE server on OpenShift in IBM Cloud as documented [here](./spire-on-openshift.md])

## Deploy Tornjak, SPIRE Server and Agents
Follow the documentation to deploy [Tornjak on Openshift](./spire-on-openshift.md#deploy-on-openshift])
with exception of enabling the `--oidc` flag:

```
# install:
utils/install-open-shift-tornjak.sh -c $CLUSTER_NAME -t $TRUST_DOMAIN -p $PROJECT_NAME --oidc
```

for example:

```console
utils/install-open-shift-tornjak.sh -c space-x.01 -t openshift.space-x.com --oidc
```

This creates an output that has a following ending:

```console
export SPIRE_SERVER=spire-server-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff-0000.us-south.containers.appdomain.cloud

Tornjak (http): http://tornjak-http-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff-0000.us-south.containers.appdomain.cloud/
Tornjak (TLS): https://tornjak-tls-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff-0000.us-south.containers.appdomain.cloud/
Tornjak (mTLS): https://tornjak-mtls-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff-0000.us-south.containers.appdomain.cloud/
Trust Domain: openshift.space-x.com
Tornjak (oidc): https://oidc-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff-0000.us-south.containers.appdomain.cloud/
  For testing oidc:

  curl -k https://oidc-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff-0000.us-south.containers.appdomain.cloud/.well-known/openid-configuration

  curl -k https://oidc-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff-0000.us-south.containers.appdomain.cloud/keys
```

Let’s test the OIDC endpoint:
```
curl -k https://oidc-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff-0000.us-south.containers.appdomain.cloud/.well-known/openid-configuration
{
  "issuer": "https://oidc-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff-0000.us-south.containers.appdomain.cloud",
  "jwks_uri": "https://oidc-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff-0000.us-south.containers.appdomain.cloud/keys",
  "authorization_endpoint": "",
  "response_types_supported": [
    "id_token"
  ],
  "subject_types_supported": [],
  "id_token_signing_alg_values_supported": [
    "RS256",
    "ES256",
    "ES384"
  ]
}
```

This output confirms that the OIDC endpoint is accessible and responds with valid information.

Let's install the [SPIRE Agents](./spire-on-openshift.md#step-2-installing-spire-agents-on-openshift):

```
oc new-project spire --description="My TSI Spire Agent project on OpenShift"
kubectl get configmap spire-bundle -n tornjak -o yaml | sed "s/namespace: tornjak/namespace: spire/" | kubectl apply -n spire -f -

export SPIRE_SERVER=spire-server-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff-0000.us-south.containers.appdomain.cloud

utils/install-open-shift-spire.sh -c space-x.01 -s $SPIRE_SERVER -t openshift.space-x.com
```

Confirm the agents were successfully deployed and get the host for the registrar:

```console
oc get po -owide
NAME                             READY   STATUS  RESTARTS AGE IP            NODE         NOMINATED NODE READINESS GATES
spire-agent-222kh                 1/1    Running   0    3m   10.38.240.206   10.38.240.206   <none>       <none>
spire-agent-6l9tf                 1/1    Running   0    3m   10.38.240.213   10.38.240.213   <none>       <none>
spire-agent-tgbmn                 1/1    Running   0    3m   10.38.240.212   10.38.240.212   <none>       <none>
spire-registrar-85fcc94797-v9q6w  1/1    Running   0    3m   172.30.118.57   10.38.240.206   <none>       <none>
```
Now follow the steps for registering the [Workload Registrar](./spire-workload-registrar.md#register-workload-registrar-with-the-spire-server) so the new workloads get SPIFFE ids.

## Start OIDC use-cases
Once the SPIRE server is enabled with OIDC plugin, we can continue the tutorial
for enabling access to [AWS S3 storage](./spire-oidc-aws-s3.md)
or [Vault secrets](./spire-oidc-vault.md).
