# Vault Plugin: JWT Auth Backend for Trusted Service Identity

This is a standalone backend plugin for use with [Hashicorp Vault](https://www.github.com/hashicorp/vault).
This plugin allows for JWTs (including OIDC tokens) to authenticate with Vault.

## Quick Links
    - Vault Website: https://www.vaultproject.io
    - JWT Auth Docs: https://www.vaultproject.io/docs/auth/jwt.html
    - Main Project Github: https://www.github.com/hashicorp/vault

This document describes the Trusted Identity demo example and provides guidance
for plugin development.

## Trusted Identity Demo
Demo with Vault Plugin steps:
* Make sure [TI Prerequisites](../../README.md#prerequisites) are met
* Install [Trusted Service Identity framework](../../REAMDE.md#install-trusted-service-identity-framework)
* [Deploy Vault Service](./README.md#deploy-vault-service)
* Configure the Vault Plugin
* Register JWT Signing Service (JSS) with Vault
* Define sample policies and roles
* Deploy Vault Client
* Execute sample transactions

## Trusted Identity Vault Authentication Plugin Development
[This section](./README.md#plugin-development) below describes the plugin development


### Deploy Vault Service
The Vault service can be started anywhere, as long as the Trusted Identity containers
can access it.

For simplicity, we will deploy the Vault Service in the same cluster and the
same `trusted-identity` namespace as Trusted Identity framework

Make sure the `KUBECONFIG` is properly set then execute:

```sh
$ kubectl -n trusted-identity create -f vault.yaml
```

In order to access this service remotely, some deployments (like IKS) require
ingress access.
For IKS, obtain the ingress name using `ibmcloud` cli:
```console
# first obtain the cluster name:
ibmcloud ks clusters
# then use the cluster name to get the Ingress info:
ibmcloud ks cluster-get <cluster_name> | grep Ingress
```
Before starting a new ingress deployment, make sure there is not other ingress deployed
in this namespace. Typical TI deployment already has an ingress running to support
access to vTPM service.
Check if the `vtpm-ingress` is created:

```
kubectl -n trusted-identity get ingress vtpm-ingress
# if the ingress already exists, dump it to the local file
kubectl -n trusted-identity get ingress vtpm-ingress -o yaml > ti-ingress.yaml
```

If exists, append the section for `ti-vault`. It should look like this:
```
. . .
http:
  paths:
  - backend:
      serviceName: vtpm-service
      servicePort: 8012
    path: /public
  - backend:
      serviceName: ti-vault
      servicePort: 8200
    path: /
```
Then just apply the update:

```
kubectl -n trusted-identity apply -f ti-ingress.yaml
```
If the ingress does not exist, build an ingress file from `ingress-IKS.template.yaml`,
using the `Ingress Subdomain` information obtained above:
```yaml
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: vault-ingress
  namespace: trusted-identity
spec:
  rules:
    # provide the actual Ingress for `host` value:
# - host: my-ti-cluster.eu-de.containers.appdomain.cloud
  - host:
    http:
      paths:
      - backend:
          serviceName: ti-vault
          servicePort: 8200
        path: /
```

create ingress:
```console
kubectl -n trusted-identity create -f ingress-IKS.yaml
```

Test the connection to vault:
```console
$ curl  http://<Ingress Subdomain or ICP master IP>/
<a href="/ui/">Temporary Redirect</a>.
```
At this point, this is an expected result.

Test the connection to vTPM:
```console
$ curl  http://<Ingress Subdomain or ICP master IP>/public/getCSR
  -----BEGIN CERTIFICATE REQUEST-----
  MIICYDCCAUgCAQAwGzEZMBcGA1UEAwwQdnRwbTItand0LXNlcnZlcjCCASIwDQYJ
  KoZIhvcNAQEBBQADggEPADCCAQoCggEBAK2ZiVYAALSs6HmJPUZDZosMS6qPaQwc
  . . . . . . . . . . . . . . . . . . .GUrDrCj7QnxyrYrgSiPu/xJvD+H
  8kW4q7nvsZm2VGKpeRpbQxj3ZlcZD2/Xm+WsKChU0wGk9qHt85qwGAzOgDfEo5Z5
  PgmLRl1PpyS3aVUBIpu8Xx+wsL5ZgVzUz1ScIi2qNPO7SqFU
  -----END CERTIFICATE REQUEST-----
```


### Configure Vault Plugin
To configure Vault and install the plugin, your system requires [vault client](https://www.vaultproject.io/docs/install/)
installation.

### Vault Setup (as Valut Admin)
To obtain access to Vault, you have to be a Vault admin.
Obtain the Vault Root token from the cluster where Vault Plugin is deployed:

```sh
$ alias kk="kubectl -n trusted-identity"
$ export ROOT_TOKEN=$(kk logs $(kk get po | grep ti-vault-| awk '{print $1}') | grep Root | cut -d' ' -f3)
```

Assign the Vault address (using Ingress tested above):

```sh
$ export VAULT_ADDR=http://<vault_address>
```
Once you have `ROOT_TOKEN` and `VAULT_ADDR` environment variables defined, test
the connection

```sh
vault login $ROOT_TOKEN
vault status
```

 Then execute the Vault plugin setup script.

```sh
$ ./demo.vault-setup.sh
```
If no errors, proceed to the JSS registration

### Register JWT Signing Service (JSS) with Vault
Each cluster with JSS needs to be registered with Vault.
Env. variables `ROOT_TOKEN` and `VAULT_ADDR` should be already defined. Now we need
the `VTPM_ADDR` for each cluster (individual vTPM). This the ingress associated
with the cluster.

e.g:
```
export VTPM_ADDR=http://ti-fra02.eu-de.containers.appdomain.cloud
```

Than execute the registration:

```sh
$ ./demo.registerJSS.sh
. . . .
Upload of x5c successful
```
Repeat this for each JSS with vTPM that is using this Vault service.


### Define sample policies and roles
Policies are structured as paths for keys based on claims provided in JWT.
By default JWT Tokens are created every 30 seconds and they are placed in `/jwt-tokens`
directory of the application. One can inspect the content of the token by simply pasting it into
[Debugger](https://jwt.io/) in Encoded window.
Sample Payload:

```json
{
  "cluster-name": "ti_demo",
  "cluster-region": "dal09",
  "exp": 1557170306,
  "iat": 1557170276,
  "images": "f36b6d491e0a62cb704aea74d65fabf1f7130832e9f32d0771de1d7c727a79cc",
  "images-names": "res-kompass-kompass-docker-local.artifactory.swg-devops.com/myubuntu:latest@sha256:5b224e11f0e8daf35deb9aebc86218f1c444d2b88f89c57420a61b1b3c24584c",
  "iss": "wsched@us.ibm.com",
  "machineid": "fa967df1a948495596ad6ba5f665f340",
  "namespace": "trusted-identity",
  "pod": "vault-cli-84c8d647c-s6cgb",
  "sub": "wsched@us.ibm.com"
}
```

Load the Vault Server with some sample polices. Review the policy templates `ti.policy.X.hcl.tpl`
and the [demo.load-sample-policies.sh](demo.load-sample-policies.sh) script.

```sh
$ ./demo.load-sample-policies.sh
```

### Start the Vault client
To start Vault client you don't need to be Vault admin (as above). You only need
access to the cluster (`KUBECONFIG`).
The vault client must be started in the cluster that has Trusted Identity installed.
Using provided template [../vault-client/vault-cli.template.yaml](../vault-client/vault-cli.template.yaml),
build the deployment file `vault-cli.yaml`, using the Vault remote address (e.g.
ingress from the steps above)


Start the vault client, then dump JWT token to be inspected.
```sh
$ kubectl -n trusted-identity create -f ../vault-client/vault-cli.yaml
$ kubectl -n trusted-identity get pods
$ kubectl -n trusted-identity exec -it {vault-cli-pod-id} cat /jwt-tokens/token
```
You can inspect the content of the token by simply pasting its content into
[Debugger](https://jwt.io/) in Encoded window.


### Load sample keys
Using the values obtained from the token above (cluster-region, cluster-name) execute
the script to populate the Vault with sample keys. These are the secrets that would
be released to the application.

```console
$ demo.load-sample-keys.sh --help
$ demo.load-sample-keys.sh [region] [cluster]
```

Then get inside to run some testing.

```console
$ kubectl -n trusted-identity get pods
$ kubectl -n trusted-identity exec -it vault-cli-xxx /bin/bash
```
To login and obtain the Vault access token associated with a default TI role `demo`,
source the `setup-vault-cli.sh`. To login with another role (e.g. demo-r or demo-n)
as specified in [demo.load-sample-policies.sh](demo.load-sample-policies.sh)
issue ` source setup-vault-cli.sh demo-r`:

```console
root@vault-cli-fd855bc5f-2cs4d:/# source ./setup-vault-cli.sh
VAULT_TOKEN=s.UCTvGwi4BcqTSBmDGt75ivd7

# if successful, view the environment related to vault:
root@vault-cli-fd855bc5f-2cs4d:/# env | grep VAULT
TI_VAULT_PORT=tcp://172.21.143.179:8200
TI_VAULT_PORT_8200_TCP_PROTO=tcp
TI_VAULT_PORT_8200_TCP_ADDR=172.21.143.179
VAULT_ROLE=demo
VAULT_TOKEN=s.UCTvGwi4BcqTSBmDGt75ivd7
TI_VAULT_SERVICE_PORT=8200
TI_VAULT_SERVICE_HOST=172.21.143.179
TI_VAULT_PORT_8200_TCP_PORT=8200
VAULT_ADDR=http://ti-fra02.eu-de.containers.appdomain.cloud:80
TI_VAULT_PORT_8200_TCP=tcp://172.21.143.179:8200
```
To test access to Vault server:

```console
root@vault-cli-fd855bc5f-2cs4d:/# vault status
Key             Value
---             -----
Seal Type       shamir
Initialized     true
Sealed          false
Total Shares    1
Threshold       1
Version         1.0.2
Cluster Name    vault-cluster-8599a725
Cluster ID      3a0aa03a-3a46-4613-ae5c-3fe9975a3800
HA Enabled      false
```

To view all the attributes (measurement) associate with this pod, you can execute
a following call:

```console
root@vault-cli-fd855bc5f-2cs4d:/# curl -s --request POST --data '{"jwt": "'"$(cat /jwt-tokens/token)"'", "role": "demo"}' ${VAULT_ADDR}/v1/auth/trusted-identity/login |jq
{
  "request_id": "61bbd112-d779-03ef-5419-3bb36eb006db",
  "lease_id": "",
  "renewable": false,
  "lease_duration": 0,
  "data": null,
  "wrap_info": null,
  "warnings": null,
  "auth": {
    "client_token": "s.Ezz0TKByMUNnuZpOxnHZ7Jgr",
    "accessor": "kvxDUNogiTfBsDNwWz4jGTOF",
    "policies": [
      "default",
      "ti-policy-all"
    ],
    "token_policies": [
      "default",
      "ti-policy-all"
    ],
    "metadata": {
      "cluster-name": "EUcluster",
      "cluster-region": "eu-de",
      "images": "f36b6d491e0a62cb704aea74d65fabf1f7130832e9f32d0771de1d7c727a79cc",
      "namespace": "trusted-identity",
      "role": "demo"
    },
    "lease_duration": 2764800,
    "renewable": true,
    "entity_id": "8c3e1e09-7bbc-bd6f-2f75-7c47486384b5",
    "token_type": "service"
  }
}
root@vault-cli-fd855bc5f-2cs4d:/#
```
The measurements are grouped under "metadata" section.

Review the test script `test-vault-cli.sh`
For example, this one is customized for `eu-de` cluster:

```console
root@vault-cli-fd855bc5f-2cs4d:/# ./test-vault-cli.sh
Testing the default demo role:
A01 Test successful! RT: 0
A02 Test successful! RT: 2
A03 Test successful! RT: 2
A04 Test successful! RT: 2
A05 Test successful! RT: 2
Testing the 'demo' role:
D01 Test successful! RT: 0
D02 Test successful! RT: 2
D03 Test successful! RT: 2
D04 Test successful! RT: 2
D05 Test successful! RT: 2
Testing the 'demo-n' role:
N01 Test successful! RT: 0
N02 Test successful! RT: 2
N03 Test successful! RT: 2
N04 Test successful! RT: 2
Testing the 'demo-r' role:
R01 Test successful! RT: 0
R02 Test successful! RT: 2
Testing non-existing role
E01 Test successful! RT: 0
Testing access w/o token
E02 Test successful! RT: 2
E03 Test successful! RT: 2
Make sure to re-run 'setup-vault-cli.sh' as this script overrides the environment value
```


## Plugin Development
### Getting Started

This is a [Vault plugin](https://www.vaultproject.io/docs/internals/plugins.html)
and is meant to work with Vault. This guide assumes you have already installed Vault
and have a basic understanding of how Vault works.

Otherwise, first read this guide on how to [get started with Vault](https://www.vaultproject.io/intro/getting-started/install.html).

To learn specifically about how plugins work, see documentation on [Vault plugins](https://www.vaultproject.io/docs/internals/plugins.html).

## Usage

Please see [documentation for the plugin](https://www.vaultproject.io/docs/auth/jwt.html)
on the Vault website.

This plugin is currently built into Vault and by default is accessed
at `auth/jwt`. To enable this in a running Vault server:

```sh
$ vault auth enable jwt
Successfully enabled 'jwt' at 'jwt'!
```

To see all the supported paths, see the [JWT auth backend docs](https://www.vaultproject.io/docs/auth/jwt.html).

## Developing the TI plugin for Vault

If you wish to work on this plugin, you'll first need
[Go](https://www.golang.org) installed on your machine.

This component is the integral part of the Trusted Service Identity project, so
please refer to installation instruction in main [README](https://github.ibm.com/kompass/TI-KeyRelease#build-and-install) to clone the repository and setup [GOPATH](https://golang.org/doc/code.html#GOPATH).

Then you can then download any required build tools by bootstrapping your
environment:

```sh
$ make bootstrap
```

Setup dependencies (this builds `vendor` directory)

```sh
$ dep ensure
```

To compile a development version of this plugin, run `make` or `make dev`.
This will put the plugin binary in the `bin` and `$GOPATH/bin` folders. `dev`
mode will only generate the binary for your platform and is faster:

```sh
$ make
$ make dev
```

Or execute `make all` to compile, build docker image and push to the artifactory repository.

```sh
$ make all
```
