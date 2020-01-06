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
Demo with Vault Plugin steps. "bootstrapping" label indicates the operations that
will be done by the initial bootstrapping in CI/CD pipeline.
* Make sure [TI Prerequisites](../../README.md#prerequisites) are met
* (bootstrapping) Install [Trusted Service Identity framework](../../REAMDE.md#install-trusted-service-identity-framework)
* [Deploy Vault Service](./README.md#deploy-vault-service)
* (bootstrapping) Configure the Vault Plugin
* (bootstrapping) Register JWT Signing Service (JSS) with Vault
* Define sample policies and roles
* Deploy Vault Client
* Execute sample transactions

Setup `kk` [alias](../../README.md#setup-kubectl-alias) to save on typing

## Trusted Identity Vault Authentication Plugin Development
[This section](./README.md#plugin-development) below describes the plugin development

### Deploy Vault Service
The Vault service can be started anywhere, as long as the Trusted Identity containers
can access it.

For simplicity, we will deploy the Vault Service in the same cluster and the
same `trusted-identity` namespace as Trusted Identity framework

Make sure the `KUBECONFIG` is properly set then execute:

```sh
$ cd examples/vault-plugin/
$ kk create -f vault.yaml
```


In order to access this service remotely, some deployments (like IKS) require
ingress access.
For IKS, obtain the ingress name using `ibmcloud` cli:
```console
$ # first obtain the cluster name:
$ ibmcloud ks clusters
$ # then use the cluster name to get the Ingress info:
$ ibmcloud ks cluster-get <cluster_name> | grep Ingress
```
Build an ingress file from `ingress-IKS.template.yaml`,
using the `Ingress Subdomain` information obtained above.
Here is an example using `my-ti-cluster.eu-de.containers.appdomain.cloud`

```yaml
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: vault-ingress
  namespace: trusted-identity
spec:
  rules:
    # provide the actual Ingress for `host` value:
  - host: my-ti-cluster.eu-de.containers.appdomain.cloud
    http:
      paths:
      - backend:
          serviceName: ti-vault
          servicePort: 8200
        path: /
```

create ingress:
```console
$ kk create -f ingress-IKS.yaml
```

Test the connection to vault:
```console
$ curl  http://<Ingress Subdomain or ICP master IP>/
<a href="/ui/">Temporary Redirect</a>.
```
At this point, this is an expected result.

### Test access to public JSS interface
For every worker node there will be a running `jss-server` and `tsi-node-setup` pod.

Test the connection to public JSS interface using the node-setup containers deployed
during the [Setup Cluster](../../README.md#setup-cluster) process earlier:

```console
# list the running pods
$ kk get pods

# select one tsi-node-setup pod and execute:
$ kk exec -it tsi-setup-tsi-node-setup-xxxx -- sh -c 'curl $HOST_IP:5000/public/getCSR'

-----BEGIN CERTIFICATE REQUEST-----
MIICXjCCAUYCAQAwGTEXMBUGA1UEAwwOanNzLWp3dC1zZXJ2ZXIwggEiMA0GCSqG
SIb3DQEBAQUAA4IBDwAwggEKAoIBAQCqeUM+TDlqhyMoRdFJA1OcPcpp4bSEDQ9W
1pgDBabCyzClJJX8BElsDi1DIf2PIhjazWMQ+rvSEP3eW0o3eLVC+XWIzIEwk/7h
o.........................................MZsg8vXKAVJdlX7npWW8Gs
yJEX/CjVKeiUZW2WLcwkFk27uDWSGXXca8Bm1kuuc01O5ENr52DEyBcjqRhMtyGb
8TYyvgfamDAth1Ph05HElSvg2mI/9Sc+qk5hLwYRC2zp8UMuKVcIlthX6t3v3ZV3
D8CthBFev8ZBzuqFQiboNG0YgJ5+JxwyVhGFPUse9fYsjQ==
-----END CERTIFICATE REQUEST-----
```

### Configure Vault Plugin
To configure Vault and install the plugin, your system requires [vault client](https://www.vaultproject.io/docs/install/)
installation.

### Vault Setup (as Valut Admin)
To obtain access to Vault, you have to be a Vault admin.
Obtain the Vault Root token from the cluster where Vault Plugin is deployed:

```sh
$ export ROOT_TOKEN=$(kk logs $(kk get po | grep ti-vault-| awk '{print $1}') | grep Root | cut -d' ' -f3)
```

Assign the Vault address (using Vault Ingress tested above):

```sh
$ export VAULT_ADDR=http://<vault_address>
# e.g.
$ export VAULT_ADDR=http://ti-fra02.eu-de.containers.appdomain.cloud
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
Env. variables `ROOT_TOKEN` and `VAULT_ADDR` should be already defined.
Execute the registration:

```sh
$ ./demo.registerJSS.sh
. . . .
Upload of x5c successful
```
This script registers every JSS node with Vault. Make sure the number `Upload of x5c successful`
corresponds to the number of nodes in the cluster (`kubectl get nodes. Node xxx completed`).

Once the registration of all JSS nodes completes, the public interface to JSS
will shut down. Testing again should return "Connection refused" failures:

```console
$ # list the running pods
$ kk get pods
$ # select one tsi-node-setup pod and execute:
$ kk exec -it tsi-setup-tsi-node-setup-xxxx -- sh -c 'curl $HOST_IP:5000/public/getCSR'
curl: (7) Failed to connect to 10.X.X.X port 5000: Connection refused
command terminated with exit code 7
```
It might take up to 30 seconds for shutting down the public interfaces

### Remove the Node Setup helm chart
At this point all nodes are registered with Vault and bootstrapping process is complete.
Remove all the node-setup containers:

```console
$ helm ls
$ helm delete --purge tsi-setup
$ # or simply use the following script:
$ helm ls --all | grep tsi-node-setup | awk '{print $1}' | sort -r| xargs helm delete --purge
```

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
  "images-names": "trustedseriviceidentity/myubuntu:latest@sha256:5b224e11f0e8daf35deb9aebc86218f1c444d2b88f89c57420a61b1b3c24584c",
  "iss": "wsched@us.ibm.com",
  "machineid": "fa967df1a948495596ad6ba5f665f340",
  "namespace": "trusted-identity",
  "pod": "vault-cli-84c8d647c-s6cgb",
  "sub": "wsched@us.ibm.com"
}
```

Load some sample policies to Vault. Review the policy templates `ti.policy.X.hcl.tpl`
and the [demo.load-sample-policies.sh](demo.load-sample-policies.sh) script.

```sh
$ ./demo.load-sample-policies.sh
```

### Preload sample keys
Preload few sample keys that are specifically customized to use with [examples/myubuntu.yaml](../myubuntu.yaml) and
[examples/vault-client/vault-cli.template.yaml](../vault-client/vault-cli.template.yaml) (see below) examples.

```console
$ demo.load-sample-keys.sh --help
$ demo.load-sample-keys.sh [region] [cluster]
```

### Start sample application
Now is time to start some sample application. The simplest one is `myubuntu`
available [here](../myubuntu.yaml#L12). Application will get a TSI sidecar as
long as it contains the following annotation:

```yaml
admission.trusted.identity/inject: "true"
```

There is also an [example](../myubuntu.yaml#L13-L33) showing how to request secrets for the application.

Start the application from a new console. It does not require Vault admin (as above).
Use `KUBECONFIG` as before, to access the cluster:

```console
cd TI-KeyRelease
kk create -f examples/myubuntu.yaml
kk get po
```

To see the keys loaded via 'demo.load-sample-policies.sh' and requested via pod annotation:

```console
kk get po
kk exec -it myubuntu-xxxx cat /tsi-secrets/mysecrets/myubuntu-mysecret1/mysecret1
```

To test the sidecar access to Vault:

```console
kk exec -it myubuntu-xxxx -c jwt-sidecar /test-vault-cli.sh
```
To see the JWT token:
```console
kk exec -it {myubuntu-pod-id} -c jwt-sidecar cat /jwt/token
```

You can inspect the content of the token by simply pasting its content into
[Debugger](https://jwt.io/) in Encoded window.


### Start the Vault client
Another example uses preloaded Vault client to access an arbitrary Vault service using the secrets obtained from TSI Vault and injected to the pod.

Using provided template [../vault-client/vault-cli.template.yaml](../vault-client/vault-cli.template.yaml),
build the deployment file `vault-cli.yaml`, using the Vault remote address.


Start the vault client, then test the injected secret:
```sh
$ kk create -f ../vault-client/vault-cli.yaml
$ kk get pods
$ kk exec -it $(kk get pods | grep vault-cli | awk '{print $1}') cat tsi-secrets/mysecrets/secret-test1/mysecret1
Defaulting container name to vault-cli.
{"all":"good"}
```

To see the JWT token:
```console
kk exec -it {vault-cli-pod-id} -c jwt-sidecar cat /jwt/token
```

You can inspect the content of the token by simply pasting its content into
[Debugger](https://jwt.io/) in Encoded window.


### Test the sidecar access to TSI Vault
Every sidecar is equipped with a test script `/test-vault-cli.sh` Assuming the keys for this pod were loaded to the Vault using `demo.load-sample-keys.sh` they should be available for testing:

```console
$ kk exec -it $(kk get pods | grep vault-cli | awk '{print $1}') -c jwt-sidecar /test-vault-cli.sh

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
R03 Test successful! RT: 0
R04 Test successful! RT: 0
Testing non-existing role
E01 Test successful! RT: 0
Testing access w/o token
E02 Test successful! RT: 2
E03 Test successful! RT: 2
Make sure to re-run 'setup-vault-cli.sh' as this script overrides the environment values
```

You can also get inside the `vault-cli` sidecar container and run other tests:

```console
$ kk exec -it $(kk get pods | grep vault-cli | awk '{print $1}') -c jwt-sidecar bash
```

To view all the attributes (measurement) associate with this pod, you can execute
a following call:

```console
root@vault-cli-fd855bc5f-2cs4d:/# curl -s --request POST --data '{"jwt": "'"$(cat /jwt/token)"'", "role": "demo"}' ${VAULT_ADDR}/v1/auth/trusted-identity/login |jq
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
