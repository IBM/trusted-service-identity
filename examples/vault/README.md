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
* Inject [secrets to Vault](./README.md#secrets)
* On-board the application

Setup `kk` [alias](/README.md#setup-kubectl-alias) to save on typing

### Deploy Vault Service
The Vault service can be started anywhere, as long as the Trusted Identity containers
can access it. Please follow the Vault installation steps from the main [README](/README.md#setup-vault)

### Configure Vault Plugin
To configure Vault and install the plugin, your system requires [vault client](https://www.vaultproject.io/docs/install/)
installation.

### Vault Setup (as Vault Admin)
*This step MUST be done in the cluster where Vault Service is deployed.*

The setup script obtains the vault admin token directly from the Vault container,
but you must provide the Vault address. In case of IKS, this is the Vault Ingress
value created earlier:

```sh
$ export VAULT_ADDR=http://<vault_address>
# e.g.
$ export VAULT_ADDR=http://tsi-test.eu-de.containers.appdomain.cloud
```

If you have a Vault client installed, you can try to get the admin token directly
This assumes the Vault is installed in `tsi-vault` namespace. For different namespace,
modify the command accordingly:

```sh
$ export ROOT_TOKEN=$(kubectl -n tsi-vault logs $(kubectl -n tsi-vault get po | grep tsi-vault-| awk '{print $1}') | grep Root | cut -d' ' -f3); echo "export ROOT_TOKEN=$ROOT_TOKEN"
```

And then test the connection:

```sh
vault login $ROOT_TOKEN
vault status
```
Vault is already setup during the installation, but if you need to set it up again
(using a default `tsi-vault` namespace):

```sh
$ ./demo.vault-setup.sh
```

Optionally, the vault address can be also passed directly to the script:

```sh
$ ./demo.vault-setup.sh $VAULT_ADDR
```

If the TSI namespace is different than `tsi-vault`,
pass the TSI namespace as follow:
```sh
$ ./demo.vault-setup.sh $VAULT_ADDR <TSI Namespace>
```
Currently, the vault setup includes the process of loading sample policies.
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

## Secrets
TSI injects the secrets to application using the file mount.
There are few sample applications available in [example/](/examples/) directory.

In order for the secrets to be injected, an application must contain an annotation
requesting the secret injection

```yaml
annotations:
  admission.trusted.identity/inject: "true"
```

The format of the secrets is following:
* `tsi.secret/name` - name of the secret, as specified in Vault
* `tsi.secret/constraints` - list of constraints that define the measurements used for validation. This typically means any combination of claim values created by TSI. To see a complete list, visit [claims](./README.md#claims). E.g, (region,images) means that only applications matching the specific region and the image will have the secret injected.
* `tsi.secret/local-path` - the location where the secret will be mounted inside the container. This path always starts with `/tsi-secrets`, so it can be a relative e.g. `mysecrets/` or absolute `/tsi-secrets/mysecrets/`.

Here are the sample secrets:

```yaml
annotations:
  admission.trusted.identity/inject: "true"
  tsi.secrets: |
       - tsi.secret/name: "mysecret1"
         tsi.secret/constraints: "region,cluster-name,namespace,images"
         tsi.secret/local-path: "mysecrets/myubuntu"
       - tsi.secret/name: "mysecret2.json"
         tsi.secret/constraints: "region,images"
         tsi.secret/local-path: "mysecrets/"
       - tsi.secret/name: "mysecret3"
         tsi.secret/constraints: "region,cluster-name,namespace"
         tsi.secret/local-path: "/tsi-secrets/mysecrets/"
```

### Application on-boarding

Before on-boarding the application, you must populate Vault with secrets, that would be injected to the application. To inject the secrets to Vault, use the script [examples/vault/demo.secret-maker.sh](/examples/vault/demo.secret-maker.sh)
This script requires a local installation of Docker.

In order to create secrets for an application, pass the application deployment file
into the script along with the namespace name.
For example, to create secrets for [examples/myubuntu.yaml](/examples/myubuntu.yaml) in `test` namespace:

```console
cd examples
vault/demo.secret-maker.sh -f myubuntu.yaml -n test
```
If using non-IKS environment, the `REGION` and `CLUSTER-NAME` values must be passed
to the script:

```console
export REGION=
export CLUSTER-NAME=
cd examples
vault/demo.secret-maker.sh -f myubuntu.yaml -n test -r $REGION -c $CLUSTER-NAME
```

The output is the script that can be used for inserting the secrets into Vault, so re-direct it to the file:

```console
vault/demo.secret-maker.sh -f myubuntu.yaml -n test > my-secrets.sh
```

This script is intended for a person, or a process, managing the secrets for the application, who has write access to the Vault.
Review the `my-secrets.sh` for any errors and provide the new values for all the secrets. Once all the secrets are specified, execute the script. This assumes the vault credentials are provided.

```console
export ROOT_TOKEN=<vault token>
export VAULT_ADDR=<vault addres>
sh ./my-secrets.sh
``

The TSI environment is ready for the application on-boarding, so create a new namespace for the application, and deploy it:

```console
export KUBECONFIG=<your cluster config>

kubectl create namespace test
kubectl -n test create -f myubuntu.yaml
kubectl -n test get po
```

The secrets will be mounted to the application container under `/tsi-secrets` directory, using the path requested via pod annotation.

Validate if the secrets were properly injected:

```console
kubectl -n test exec -it $(kubectl -n test get pods | grep myubuntu | awk '{print $1}') ls /tsi-secrets/mysecrets

kubectl -n test exec -it $(kubectl -n test get pods | grep myubuntu | awk '{print $1}') cat /tsi-secrets/mysecrets/mysecret2
```

## Claims
By default JWT Tokens are created every 60 seconds and they are placed in `/jwt-tokens`
directory of the application sidecar.
To inspect the current claim for a running application, use the `demo.claim-reviewer.sh` script.

```console
kubectl -n test get po
NAME                        READY   STATUS    RESTARTS   AGE
myubuntu-7b8969b898-gmzhf   2/2     Running   0          2h
vault/demo.claim-reviewer.sh myubuntu-7b8969b898-gmzhf test
```
and the output might be:

```json
{
  "cluster-name": "ti-test1",
  "exp": 1592221326,
  "iat": 1592221266,
  "images": "30beed0665d9cb4df616cca84ef2c06d2323e02869fcca8bbfbf0d8c5a3987cc",
  "images-names": "ubuntu@sha256:250cc6f3f3ffc5cdaa9d8f4946ac79821aafb4d3afc93928f0de9336eba21aa4",
  "iss": "wsched@us.ibm.com",
  "machineid": "b46e165c32d342d9896d9eeb43c4d5dd",
  "namespace": "test",
  "pod": "myubuntu-7b8969b898-gmzhf",
  "region": "eu-de",
  "sub": "wsched@us.ibm.com"
}

Alternatively, the JWT token can be obtained directly from the sidecar:

```console
kubectl -n test exec -it myubuntu-7b8969b898-gmzhf -c jwt-sidecar cat /jwt/token
```
and inspected by simply pasting it into [Debugger](https://jwt.io/) in Encoded window.

### More testing and exploring
Get inside the sidecar:

```console
$ kubectl -n test exec -it myubuntu-xxxx -c jwt-sidecar bash
```

Get secret from Vault using JWT token:

```console
curl --request POST --data '{"jwt": "'"$(cat /jwt/token)"'", "role": "'tsi-role-r'"}' "${VAULT_ADDR}"/v1/auth/trusted-identity/login | jq

export VAULT_TOKEN=$(echo $RESP | jq -r '.auth.client_token')

export VAULT_TOKEN=$(curl --request POST --data '{"jwt": "'"$(cat /jwt/token)"'", "role": "'tsi-role-r'"}' "${VAULT_ADDR}"/v1/auth/trusted-identity/login | jq -r '.auth.client_token')

vault kv get -format=json secret/tsi-r/eu-de/mysecret2
```

To view all the attributes (measurement) associate with this pod, you can execute
a following call:

```console
root@vault-cli-fd855bc5f-2cs4d:/# curl -s --request POST --data '{"jwt": "'"$(cat /jwt/token)"'", "role": "tsi-role-r"}' ${VAULT_ADDR}/v1/auth/trusted-identity/login |jq
{
  "request_id": "fbd9e2f3-6eba-e4f4-4b41-2e6a320810ba",
  "lease_id": "",
  "renewable": false,
  "lease_duration": 0,
  "data": null,
  "wrap_info": null,
  "warnings": null,
  "auth": {
    "client_token": "s.LlqsTxXxXT4bRTU5L8l5RaFN",
    "accessor": "7kaLfoKDo2iZsGoU4FRUkKc4",
    "policies": [
      "default",
      "tsi-policy-r"
    ],
    "token_policies": [
      "default",
      "tsi-policy-r"
    ],
    "metadata": {
      "region": "eu-de",
      "role": "tsi-role-r"
    },
    "lease_duration": 2764800,
    "renewable": true,
    "entity_id": "7a01b56f-8d6b-4e47-3aab-ede31152df58",
    "token_type": "service",
    "orphan": true
  }
}
root@vault-cli-fd855bc5f-2cs4d:/#
```
The measurements are grouped under "metadata" section. The members of "metadata"
depend on the `role` value used for login.

Here is a sample for role `tsi-policy-rcni`:
```json
"metadata": {
  "cluster-name": "ti-test1",
  "images": "30beed0665d9cb4df616cca84ef2c06d2323e02869fcca8bbfbf0d8c5a3987cc",
  "namespace": "test",
  "region": "eu-de",
  "role": "tsi-role-rcni"
}
```
