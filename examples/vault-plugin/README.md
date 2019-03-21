# Vault Plugin: JWT Auth Backend for Trusted Service Identity

This is a standalone backend plugin for use with [Hashicorp Vault](https://www.github.com/hashicorp/vault).
This plugin allows for JWTs (including OIDC tokens) to authenticate with Vault.


## Quick Links
    - Vault Website: https://www.vaultproject.io
    - JWT Auth Docs: https://www.vaultproject.io/docs/auth/jwt.html
    - Main Project Github: https://www.github.com/hashicorp/vault

## Getting Started

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

## Start the Vault Service and configure the TI plugin
The Vault service can be started anywhere, as long as the Trusted Identity containers
can access it.

For simplicity, we will deploy the Vault Service in the same cluster and the
same `trusted-identity` namespace as the initial TI demo.

Make sure the KUBECONFIG is properly set then execute:

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

Build an ingress file from `ingress-IKS.template.yaml`, using the `Ingress Subdomain` information
 obtained above:
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
kubectl -n trusted-identity create ingress-IKS.yaml
```

Test the connection:
```console
$ curl  http://<Ingress Subdomain or ICP master IP>/
<a href="/ui/">Temporary Redirect</a>.
```
At this point, this is an expected result.

## Obtain public JWKS for each vTPM deployment
For every deployment of vTPM, obtain JWKS to configure Vault Plugin.

In order to obtain JWKS, connect to any container deployed in the same
`trusted-identity` namespace as vTPM and get it using `curl http://vtpm-service:8012/getJWKS`.

As an example, let's create and connect to `myubuntu`, replace the end-of-line with `\n`
and redirect the JWKS into a file `jwks.json`:

```console
$ alias k="kubectl -n trusted-identity"
$ k create -f ../examples/myubuntu.yaml
$ k exec -it $(k get po | grep myubuntu | awk '{print $1}') /bin/bash
root@myubuntu-698b749889-pdp78:/# curl http://vtpm-service:8012/getJWKS | awk '{printf "%s\\n", $0}' > jwks.json
```

Copy the `jwks.json` to your development machine where you have cloned this repo,
to complete the Vault plugin setup.

Obtain the Vault Root Token:
```sh
$ export ROOT_TOKEN=$(k logs $(k get po | grep ti-vault-| awk '{print $1}') | grep Root | cut -d' ' -f3)
```

Assign the Vault address (using Ingress tested above):

```sh
$ export VAULT_ADDR=http://<vault_address>
```
Once you have `ROOT_TOKEN` and `VAULT_ADDR` environment variables defined, execute
the Vault plugin setup script.

```sh
$ ./demo.vault-setup.sh
```

Load the Vault Server with some sample polices. Review the `ti.policy.X.hcl.tpl`
templates and the [demo.load-sample-policies.sh](demo.load-sample-policies.sh) script.

```sh
$ ./demo.load-sample-policies.sh
```

## Start the Vault client

The vault client must be started in the cluster that has Trusted Identity installed.
Using provided template [../vault-client/vault-cli.template.yaml](../vault-client/vault-cli.template.yaml),
build the deployment file `vault-cli.yaml`, using the Vault remote address (e.g.
ingress from the steps above)

```sh
$ kubectl -n trusted-identity -f ../vault-plugin/vault-cli.yaml
```

Once the pod is operational, get inside to run some testing.

```console
$ kubectl -n trusted-identity get pods
$ kubectl -n trusted-identity vault-cli-xxxx /bin/bash
```
To login and obtain the Vault access token associated with a default TI role `demo`,
source the `setup-vault-cli.sh`:

```console
root@vault-cli-fd855bc5f-2cs4d:/# . ./setup-vault-cli.sh
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

Review the test scripts `test-vault-cli.xx.sh`
For example, this one is customized for `eu-de` cluster:

```console
root@vault-cli-fd855bc5f-2cs4d:/# ./test-vault-cli.eu-de.sh
Testing the default demo role:
A01 Test successful! RT: 0
A02 Test successful! RT: 2
A03 Test successful! RT: 2
A04 Test successful! RT: 2
A05 Test successful! RT: 2
A06 Test successful! RT: 0
A07 Test successful! RT: 2
A08 Test successful! RT: 2
A09 Test successful! RT: 0
A10 Test successful! RT: 2
A11 Test successful! RT: 0
A12 Test successful! RT: 2
A13 Test successful! RT: 2
A14 Test successful! RT: 2
Testing the 'demo' role:
D01 Test successful! RT: 0
D02 Test successful! RT: 2
D03 Test successful! RT: 2
D04 Test successful! RT: 2
D05 Test successful! RT: 2
D06 Test successful! RT: 0
D07 Test successful! RT: 2
D08 Test successful! RT: 2
D09 Test successful! RT: 0
D10 Test successful! RT: 2
D11 Test successful! RT: 0
D12 Test successful! RT: 2
D13 Test successful! RT: 2
D14 Test successful! RT: 2
D15 Test successful! RT: 2
D16 Test successful! RT: 2
Testing the 'demo-n' role:
N01 Test successful! RT: 2
N02 Test successful! RT: 0
N03 Test successful! RT: 2
N04 Test successful! RT: 2
N05 Test successful! RT: 2
N06 Test successful! RT: 0
N07 Test successful! RT: 2
N08 Test successful! RT: 2
N09 Test successful! RT: 2
N10 Test successful! RT: 2
Testing the 'demo-r' role:
R01 Test successful! RT: 2
R02 Test successful! RT: 0
R03 Test successful! RT: 0
R04 Test successful! RT: 2
R05 Test successful! RT: 2
R06 Test successful! RT: 2
Testing non-existing role
E01 Test successful! RT: 0
Testing access w/o token
E02 Test successful! RT: 2
E03 Test successful! RT: 2
Make sure to re-run 'setup-vault-cli.sh' as this script overrides the environment values
```
