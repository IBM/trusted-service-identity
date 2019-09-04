# Contributing and Developing Trusted Service Identity

If you are interested in contributing and developing the Trusted Service Identity
follow the steps below.

## Prerequisites
* Before starting, please make sure all the [Prerequisites](./README.md#prerequisites)
are satisfied.
*  Make sure you have an IBM Cloud (formerly Bluemix) account and you have the [IBM Cloud CLI](https://cloud.ibm.com/docs/cli?topic=cloud-cli-ibmcloud-cli) installed


## Build and Install
[Install](https://github.com/golang/dep#installation) and execute `dep` to manage GoLang dependencies for this project.

To compile and build the image, get and test the dependencies:

```console
make dep get-deps test-deps
```
This might take some time to execute as it scans and installs the dependencies.
Once the dependencies are installed, execute the build.

Regenerating deep copy

Deep copy helpers are required for the data schema. A data copy helper (of the form zz_generated.deepcopy.go) already exists for this app under pkg/apis/cti/v1, however if change the schema you will need to regenerate it.

To regenerate, simply run the following script from the root of this project:

```
hack/update-codegen.sh
```

this will update the pkg/client directory. If everything OK, following message appears:

```
diffing hack/../pkg against freshly generated codegen
hack/../pkg up to date.
```

```console
make build
```

Now you can create a docker image:

```console
make docker
```

Compile and create images for other sub-components

```console
make all -C components/gen-vault-cert/
make all -C components/jss/
make all -C components/jwt-sidecar/
make all -C components/node-setup/
make all -C components/revoker/
```
vTPM is no longer a required component, but if you like to still use it, either version
vTPM v1 or v2, built them as shown below and then referenced accordingly in the
helm deployment.

```console
make all -C components/vtpm-server/
make all -C components/vtpm2-server/
```

Compile and build examples (JWT server and client)

```console
make all -C examples/vault-client/
make all -C examples/vault-plugin/
make all -C examples/jwt-client/
make all -C examples/jwt-server/
```

## TI Key Release Helm Deployment
The deployment is done in `trusted-identity` namespace. If you are testing or developing
the code and execute the deployment several time, it is a good idea to cleanup the namespace before executing another deployment.

Update [init-namespace.sh](./init-namespace.sh) per instructions above.
Run cleanup first, then init to initialize the namespace. This would remove all
the components and artifacts, then recreate a new, empty namespace:

```console
./cleanup.sh
./init-namespace.sh
```

## New cluster setup
All the worker hosts are required to be initialized with private keys, either directly
or via vTPM. This operation needs to be executed only once.

### Build Node Setup chart
Package the helm chart:
```console
helm package charts/tsi-node-setup
```

Now, follow the steps to [setup cluster](./README.md#setup-cluster)

## Build Trusted Service Identity framework charts
Currently there are 2 charts to deploy Trusted Service Identity:
* ti-key-release-1
* ti-key-release-2

Package the helm charts:
```console
cd TI-KeyRelease
helm package charts/ti-key-release-1
# update helm dependencies
helm dep update charts/ti-key-release-2
helm package --dependency-update charts/ti-key-release-2
```
Your new helm chart, `ti-key-release-2-x.X.x.tgs` already contains `ti-key-release-1`
and it is ready deploy.
To be consistent, move the newly created chart package into `charts` directory.

Once the helm charts are created, you can proceed with [install](./REAMDE.md#install-trusted-service-identity-framework) of the Trusted Service Identity framework




## Automate Vault Certificates
Optionally, Trusted Service Identity can additionally create a unique set of a
certificate and private key that is automatically registered with Vault service.
The certificates with x509v3 extended attributes are enclosed in the claims in the tokens.
The difference is that these certificates are not set to have a short expiry.
Once the pod is removed, the certificates would be revoked from the Vault.
In order to use this feature, one time host setup is required. See below.

### Deploy TI Setup

Get the default chart values and replace them with your private keys and certs.
Replace X.X.X with proper version numbers

```console
helm inspect values charts/ti-setup-X.X.X.tgz > config.yaml
# modify config.yaml with your own values
helm install charts/ti-setup-X.X.X.tgz --values=config.yaml --debug --name ti-setup
```

Once the `ti-setup` is successfully deployed, remove it.
```console
helm delete --purge ti-setup
```

To validate and inspect the values assigned by the setup chart, run the daemonset to access all the hosts:

```console
kubectl create -f examples/inspect-daemonset.yaml
kubectl get pods
# select the node that you like to inspect and get inside:
kubectl exec -it <pod_id> /bin/bash
# review /host/ti/secrets, /etc/machineid, /keys/
```

To remove/reset all the values setup by the `ti-setup` chart, run the following:

```console
kubectl create -f examples/cleanup-daemonset.yaml
kubectl delete -f examples/cleanup-daemonset.yaml
```

### Install TI with `Create Vault Certificate` option turned on
After the initial host setup is complete, execute the TI Helm install.
Make sure the `ti-key-release-1.createVaultCert=true`. This can be done
either via CLI:

```console
helm install charts/ti-key-release-2-X.X.X.tgz --debug --name ti-test \
--set ti-key-release-1.cluster.name=ti-fra02 \
--set ti-key-release-1.cluster.region=eu-de \
--set ingress.host=ti-fra02.eu-de.containers.appdomain.cloud \
--set ti-key-release-1.createVaultCert=true
```
or by modifying the configuration values:
```
helm inspect values charts/ti-key-release-2-X.X.X.tgz > config.yaml
# modify config.yaml with ti-key-release-1.createVaultCert=true
helm install -i --values=config.yaml ti-test charts/ti-key-release-2-X.X.X.tgz
```

# OLD DOCUMENTATION. It might not be relevant anymore...

## Create your own private key and public JSON Web Key Set (JWKS)
Before enabling the JWT policy in Istio, you need to first create a private key
and JWKS. The following steps are based on [this doc](https://github.com/istio/istio/blob/release-1.0/security/tools/jwt/samples/README.md)
This can be done from inside the sidecar container:

```console
kubectl -n trusted-identity exec -it <my_ubuntu_pod_id> -c jwt-sidecar /bin/bash
# generate private key using openssl
openssl genrsa -out key.pem 2048
# run gen-jwt.py with --jkws to create new public key set (JWKS) and sample JWT
python gen-jwt.py key.pem -jwks=./jwks.json --expire=60 --claims=foo:bar > demo.jwt
```

Preserve the newly created `key.pem` and `jwks.json`. Put the public JWKS to publicly accessible place e.g.
https://raw.githubusercontent.com/mrsabath/jwks-test/master/jwks.json in public GITHUB: https://github.com/mrsabath/jwks-test/blob/master/jwks.json

Put the private key to [./charts/ti-key-release-2/values.yaml](./charts/ti-key-release-2/values.yaml)

```yaml

ti-key-release-1:
  jwtkey: |-
    -----BEGIN RSA PRIVATE KEY-----
    MIIEogIBAAKCAQEAtRcoFKRhV5+1w3r9ZrDeT4XKaREaher2dAfg0i82Te2QG1B5
    . . . .
         ***** MY KEY *****
    . . . .
    Au57AoGALTlcO/AMzyj/UjE+/6wP0nYuw90FitYq9h9q9jSYIMyxwQWJa4qWwkp9
    0vuUNDqsbzFeqqG55f0FZp3bfmNExNs0igdcTzwfqt6Q4LGkZVFYicbshIxHDC0a
    fn3/DuZcMg+chQ970y+XF5JtUwgVbYfaMiP1zrF0J6Fh4rHk3Cw=
    -----END RSA PRIVATE KEY-----
```
Then redeploy the charts and your container.


# Trusted Identity with Istio
In this demo we will start a web service with Istio Envoy, enable Istio policy
to require JWT tokens to communicate with this service, then start a container with
corresponding sidecar to manage creation of JWT tokens. Only the tokens created by
a sidecar will be accepted by the Envoy. All other requests will be rejected.

For simplicity, we will use the same namespace for all the transactions.

## Start a web service with Istio Envoy
Use provided [examples/web-service.yaml] service for deployment with a sidecar:

```console
kubectl apply -n trusted-identity -f <(./istioctl kube-inject -f examples/web-service.yaml)
```

## Enable the JWT policy for Istio
In order to use the JWT tokens to authenticate the end-user, enable Istio policy
referencing prebuilt public key from [here](https://raw.githubusercontent.com/mrsabath/jwks-test/master/jwks.json)
To use your own set of keys, see instructions at the bottom of this page

```yaml
apiVersion: "authentication.istio.io/v1alpha1"
kind: "Policy"
metadata:
  name: "jwt-example"
spec:
  targets:
  - name: web-service
  origins:
  - jwt:
      issuer: "wsched@us.ibm.com"
      jwksUri: "https://raw.githubusercontent.com/mrsabath/jwks-test/master/jwks.json"
  principalBinding: USE_ORIGIN
```

Install the policy [examples/jwt-policy-example.yaml](./examples/jwt-policy-example.yaml)

```console
kubectl create -f examples/jwt-policy-example.yaml -n trusted-identity
```

## Testing the JWT token created by the sidecar
Every container created in `trusted-identity` namespace that conforms to [this
policy](./charts/ti-key-release-1/templates/cti-policy-example.yaml) gets a sidecar
that is creating JWT tokens as defined by `execute-get-key.sh` in [here](./components/jwt-sidecar/execute-get-key.sh)
This newly created token is available to the main container via shared mount (`/jwt-tokens/token`)

For testing purposes the sidecar creates a token valid 30 seconds and the refresh
rate is 25 seconds, so the application gets a new token 5 seconds before the old
one expires.

If you don't have the container running from previous steps, start it now:
```
console
kubectl -n trusted-identity create -f examples/myubuntu_inject.yaml
```

Login to this container and try to execute a connection to the web service.

```console
kubectl -n trusted-identity get pods
kubectl -n trusted-identity exec -it <my_ubuntu_pod_id> -c myubuntu /bin/bash

root@myubuntu-767584864-b76f8:/# curl web-service
Origin authentication failed.
root@myubuntu-767584864-b76f8:/#
```

Since we enabled the Istio policy, the web service's Envoy requires valid JWT token
to be provided in order to grant access to the server, so now let's try to connect
with newly created JWT token:

```console
# run endless loop to test the connection
while true; do curl --header "Authorization: Bearer $(cat /jwt-tokens/token)" web-service -s -w "%{http_code}\n";sleep 5; done
```
Now you should be getting valid web service responses
You can copy the JWT token from /jwt-tokens/token and inspect it (e.g. [https://jwt.io/](https://jwt.io/))
