# Trusted Service Identity Demo with Vault
This demo uses the [TSI Vault authentication plugin](/components/vault-plugin/README.md)

## Trusted Identity Vault Authentication Plugin Development
[This section](/components/vault-plugin/README.md#plugin-development) describes the plugin development

## Trusted Identity Demo
Demo with Vault Plugin steps. "bootstrapping" label indicates the operations that
will be done by the initial bootstrapping in CI/CD pipeline.
* Make sure [TI Prerequisites](/README.md#prerequisites) are met
* (bootstrapping) Install [Trusted Service Identity framework](/README.md#install-trusted-service-identity-framework)
* [Deploy Vault Service](/README.md#deploy-vault-service)
* (bootstrapping) Configure the Vault Plugin
* (bootstrapping) Register JWT Signing Service (JSS) with Vault
* Define sample policies and roles
* Deploy Vault Client
* Execute sample transactions

Setup `kk` [alias](/README.md#setup-kubectl-alias) to save on typing

### Deploy Vault Service
The Vault service can be started anywhere, as long as the Trusted Identity containers
can access it. Please follow the Vault installation steps from the main [README](/README.md#setup-vault)

### Configure Vault Plugin
To configure Vault and install the plugin, your system requires [vault client](https://www.vaultproject.io/docs/install/)
installation.

### Vault Setup (as Vault Admin)
*This step MUST be done in the cluster where Vault Service is deployed.*

To obtain access to Vault, you have to be a Vault admin.
Obtain the Vault Root token from the cluster where Vault Plugin is deployed:

```sh
$ export ROOT_TOKEN=$(kk logs $(kk get po | grep tsi-vault-| awk '{print $1}') | grep Root | cut -d' ' -f3)
```

Assign the Vault address (using Vault Ingress tested above):

```sh
$ export VAULT_ADDR=http://<vault_address>
# e.g.
$ export VAULT_ADDR=http://tsi-test.eu-de.containers.appdomain.cloud
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
If the TSI namespace is different than `trusted-identity`,
pass the TSI namespace as follow:
```sh
$ ./demo.vault-setup.sh $ROOT_TOKEN $VAULT_ADDR <TSI Namespace>
```
If no errors, proceed to the JSS registration

### Register JWT Signing Service (JSS) with Vault
*This step MUST be done in the cluster that you want to register with Vault.*

If vault was deployed in a different cluster, obtain the ROOT_TOKEN from Vault
and VAULT_ADDR (see the Vault Setup steps above):

```console
export VAULT_ADDR=http://<vault_address>
export ROOT_TOKEN=<token>
```

Before registering the JSS service with Vault, please test the access to public JSS
interface.
For every worker node there will be a running `jss-server` (or `vtpm2-server`
when using vTPM2) and `tsi-node-setup` pod.

Test the connection to public JSS interface using the node-setup containers deployed
during the [Setup Cluster](/README.md#setup-cluster) process earlier:

```console
$ kk exec -it $(kk get po | grep tsi-node-setup | awk '{print $1}' |  sed -n 1p ) -- sh -c 'curl $HOST_IP:5000/public/getCSR'

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

Each node, member of the cluster, needs to be registered with Vault.
The env. variables `ROOT_TOKEN` and `VAULT_ADDR` must be defined.

Execute the registration:

```sh
$ ./demo.registerJSS.sh
. . . .
Upload of x5c successful
```
If the TSI namespace is different than `trusted-identity`,
pass the TSI namespace as follow:
```sh
$ ./demo.registerJSS.sh $ROOT_TOKEN $VAULT_ADDR <TSI Namespace>
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
$ # or simply use the following script:
$ kk exec -it $(kk get po | grep tsi-node-setup | awk '{print $1}' |  sed -n 1p ) -- sh -c 'curl $HOST_IP:5000/public/getCSR'
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
  "region": "dal09",
  "exp": 1557170306,
  "iat": 1557170276,
  "images": "f36b6d491e0a62cb704aea74d65fabf1f7130832e9f32d0771de1d7c727a79cc",
  "images-names": "trustedseriviceidentity/myubuntu@sha256:5b224e11f0e8daf35deb9aebc86218f1c444d2b88f89c57420a61b1b3c24584c",
  "iss": "wsched@us.ibm.com",
  "machineid": "fa967df1a948495596ad6ba5f665f340",
  "namespace": "test",
  "pod": "vault-cli-84c8d647c-s6cgb",
  "sub": "wsched@us.ibm.com"
}
```

Load some sample policies to Vault. Review the policy templates `ti.policy.X.hcl.tpl`
and the [demo.load-sample-policies.sh](demo.load-sample-policies.sh) script.

```sh
$ ./demo.load-sample-policies.sh
```

## Secrets 
### Preload sample keys
Preload few sample keys that are specifically customized to use with [examples/myubuntu.yaml](/examples/myubuntu.yaml) (see example below).

Since version 1.4, the application must be running in a separate namespace. Use
*the application namespace*  to load the sample keys:
```console
$ demo.load-sample-keys.sh --help
$ demo.load-sample-keys.sh [region] [cluster] [app. namespace]
```

### Start sample application
Now is time to start some sample application. The simplest one is `myubuntu`
available [here](/examples/myubuntu.yaml). Application will get a TSI sidecar as long
as it contains the following annotation:

```yaml
admission.trusted.identity/inject: "true"
```
There is also an [example](/examples/myubuntu.yaml#L16-L40) showing how to request secrets for the application.

Staring with TSI version 1.4, all applications must be
created in a namespace that is not used for TSI components e.g. _test_

Start the application from a new console. It does not require Vault admin (as above).
Use `KUBECONFIG` as before, to access the cluster:

```console
export KUBECONFIG=<your cluster config>
cd TI-KeyRelease
kubectl create namespace test
kubectl -n test create -f examples/myubuntu.yaml
kubectl -n test get po
```

The secrets will be mounted to your pod under `/tsi-secrets` directory, using
the path requested via pod annotation.

Validate if the sample secrets loaded earlier to Vault via 'demo.load-sample-keys.sh'  script and
requested via pod annotation are available on the container:

```console
kubectl -n test exec -it $(kubectl -n test get pods | grep myubuntu | awk '{print $1}') cat /tsi-secrets/mysecrets/mysecret4
```

To test the sidecar access to Vault:

```console
$ kubectl -n test exec -it myubuntu-xxxx -c jwt-sidecar /test-vault-cli.sh
# or
$ kubectl -n test exec -it $(kubectl -n test get pods | grep myubuntu | awk '{print $1}') -c jwt-sidecar /test-vault-cli.sh
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
R05 Test successful! RT: 0
Testing non-existing role
E01 Test successful! RT: 0
Testing access w/o token
E02 Test successful! RT: 2
E03 Test successful! RT: 2
Make sure to re-run 'setup-vault-cli.sh' as this script overrides the environment values
```

To see the JWT token:
```console
kubectl -n test exec -it {myubuntu-pod-id} -c jwt-sidecar cat /jwt/token
```

You can inspect the content of the token by simply pasting its content into
[Debugger](https://jwt.io/) in Encoded window.

### More testing and exploring
Get inside the sidecar:

```console
$ kubectl -n test exec -it myubuntu-xxxx -c jwt-sidecar bash
```

Get secret from Vault using JWT token:

```console
curl --request POST --data '{"jwt": "'"$(cat /jwt/token)"'", "role": "'demo-r'"}' "${VAULT_ADDR}"/v1/auth/trusted-identity/login | jq

export VAULT_TOKEN=$(echo $RESP | jq -r '.auth.client_token')

export VAULT_TOKEN=$(curl --request POST --data '{"jwt": "'"$(cat /jwt/token)"'", "role": "'demo-r'"}' "${VAULT_ADDR}"/v1/auth/trusted-identity/login | jq -r '.auth.client_token')

vault kv get -format=json secret/ti-demo-r/eu-de/mysecret4
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
      "region": "eu-de",
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
The measurements are grouped under "metadata" section. The members of "metadata"
depend on the `role` value used for login
