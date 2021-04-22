# Trusted Service Identity (TSI)

Trusted Service Identity by IBM Research is closing the gap of preventing access
to secrets by an untrusted operator during the process of obtaining authorization
for data access by the applications running in the public cloud.

The project ties Key Management Service technologies with identity via host
provenance and integrity.

TSI limits access to keys (credentials, secrets) for service provider administrators,
by creating a key/credential release system based on authorization of container
workloads. Each application that requires access to key gets a short-term identity
in form of a JSON Web Token (JWT) as a digital biometric identity that is bound
to the process and signed by a chain of trust that originates from
physical hardware. Secrets are released to the application based on this identity.

## Table of Contents
- [Installation](./README.md#installation)
  - [Prerequisites](./README.md#prerequisites)
  - [Attestation](./README.md#attestation)
  - [Openshift](./README.md#openshift)
  - [Setup Vault](./README.md#setup-vault)
  - [Setup Cluster](./README.md#setup-cluster-nodes)
  - [Sidecar options](./README.md#sidecar)
  - [Install](./README.md#install-trusted-service-identity-framework)
  - [Test](./README.md#testing-deployment)
  - [Cleanup](./README.md#cleanup)
- [Usage (demo)](examples/README.md)
- [Security considerations](./README.md#security-considerations)
- [Reporting security issues](./README.md#reporting-security-issues)
- [Contributing (TSI Development)](./CONTRIBUTING.md)
- [Maintainers List](./MAINTAINERS.md##maintainers-list)

## Installation

### Prerequisites
#### Clone this project in a local directory, outside your GOPATH
```console
git clone git@github.com:IBM/trusted-service-identity.git
cd trusted-service-identity
```

#### Kubernetes cluster
* Trusted Service Identity requires Kubernetes cluster. You can use [IBM Cloud Kubernetes Service](https://www.ibm.com/cloud/container-service/),
[IBM Cloud Private](https://www.ibm.com/cloud/private), [Openshift](https://docs.openshift.com/container-platform/3.3/install_config/install/quick_install.html) or [minikube](https://github.com/kubernetes/minikube) or any other solution that provides Kubernetes cluster.
* The installation was tested using Kubernetes version 1.16 and higher
* Make sure the Kubernetes cluster is operational and you can access it remotely using [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) tool
* Make sure the `KUBECONFIG` is properly set and you can access the cluster. Test the access with
```console
export KUBECONFIG=<location of your Kubernetes configuration files, as per documentation for your cluster>
kubectl get pods --all-namespaces
```

#### Setup kubectl alias
Through out this whole project we will be working with the newly created TSI namespace.
By default it is `trusted-identity`, but it can be changed as needed.
Let's setup an alias `kk` to make typing faster. The value can be anything, but stay
consistent:
```console
$ alias kk="kubectl -n trusted-identity"
$ # list all objects to test it
$ kk get all
```

#### Install and initialize Helm environment
The OpenShift installation, only needs the helm client installed. There is no
need to run the `helm init` operation.

This project requires Helm v2.10.0 or higher, but not Helm v3 (yet...)
Install [Helm](https://github.com/kubernetes/helm/blob/master/docs/install.md). On Mac OS X you can use brew to install helm:
```bash
  brew install kubernetes-helm
  # or to upgrade the existing helm
  brew upgrade kubernetes-helm
  # then initialize (assuming your KUBECONFIG for the current cluster is already setup)
  helm init
```
*NOTE*: If you are using IBM Cloud Kubernetes Service, with K8s version 1.12 or higher,
the kube-system default service account no longer has cluster-admin access to the Kubernetes API.
Executing any helm operations might cause a following error:
```
Error: customresourcedefinitions.apiextensions.k8s.io "clustertis.trusted.identity" is forbidden: User "system:serviceaccount:kube-system:default" cannot delete resource "customresourcedefinitions" in API group "apiextensions.k8s.io" at the cluster scope
```

As a quick fix you can do a following

```console
kubectl --namespace kube-system create serviceaccount tiller
kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller
helm init --service-account tiller --upgrade
```
or simply execute provided [script](./setup-tiller.sh):
```console
./setup-tiller.sh
```

another option (see [this](https://cloud.ibm.com/docs/containers?topic=containers-cs_versions#112_before) for more details):
```console
kubectl create clusterrolebinding kube-system:default --clusterrole=cluster-admin --serviceaccount=kube-system:default
```

#### Installation images
The images are publicly available from Docker hub. For example, [https://hub.docker.com/repository/docker/tsidentity/ti-webhook](https://hub.docker.com/repository/docker/tsidentity/ti-webhook)

The deployment is done in `trusted-identity` namespace. If you are testing
or developing the code and execute the deployment several times, it is a good
idea to cleanup the namespace before executing another deployment. Run cleanup
first, then init to initialize the namespace.
This would remove all the components and artifacts.

Then recreate a new, empty namespace:

```console
./utils/cleanup.sh
./utils/init-namespace.sh
```

### Attestation
Attestation is the process of providing a digital signature of a set of measurements
securely stored in hardware, then having the requestor validate the signature and
the set of measurements. Attestation requires the roots of trust. The platform has to have a Root of Trust for Measurement (RTM) that is implicitly trusted to provide an accurate measurement and enhanced hardware-based security features provide the RTM.

TSI requires an attestation process to accurately define the identity of the worker
nodes hosting the application containers. The simplest attestation is via software, `soft` (default) that relies on the trusted bootstrapping process or administrator
that is performing the TSI installation. The values for CLUSTER_NAME and REGION
are passed as arguments to the Helm deployment.

Another option is an experimental work with Intel using Intel's Verification Server
[IsecL](https://01.org/intel-secl). This process requires two independent phases:
- Asset Registration with Intel Verification Server (executed on every individual worker node by executing [setIdentity.sh](./components/tsi-util/setIdentity.sh) script included in `tsi-util` image: ):
  1. We need TSI fields that we want to use for creating ASSET_TAG:
    ```console
    export CLUSTER_NAME=(cluster name)
    export REGION=(region name)
    ```
  1. We need Intel Attestation Server creds (ISecL authentication service credentials are configured in populate-users.env)
  ```console
  export ISECL_USERNAME=
  export ISECL_PASSWD=
  ```
  1. Next are the ISecL endpoints that can be obtained by running `tagent export-config --stdout`:
  ```console
  export AUTH_ENDPOINT=(value of aas.api.url)
  export ISECL_ENDPOINT=(value of mtwilson.api.url)
  export NODEHOSTNAME=(hostname of the worker node)
  ```
  1. Execute the script to register the ASSET_TAG:
    ```console
    docker run --rm --name=setIdent \
    --env NODEHOSTNAME="$NODEHOSTNAME" \
    --env VER_SERV_USERNAME="$ISECL_USERNAME" \
    --env VER_SERV_PASSWD="$ISECL_PASSWD" \
    --env TOKEN_SERVICE="$AUTH_ENDPOINT" \
    --env VER_SERVICE="$ISECL_ENDPOINT" \
    tsidentity/tsi-util:v1.8.0 /bin/bash -c "/usr/local/bin/setIdentity.sh $REGION $CLUSTER_NAME"
    ```
    This script creates an ASSET_TAG Flavor and deploys it to the Verification Server. As a result, the server calculates the hash of the certificate, calls the Intel Trust Agent for the given host to store the tag info in local TPM. As soon as the tag is provisioned, the attestation report will include the newly created tag value for each Security Assertion Markup Language (SAML) report.

    The format of the ASSET_TAG is following:
    ```json
    {
       "hardware_uuid": "${HW_UUID}",
       "selection_content": [ {
           "name": "region",
           "value": "${REGION}"
          }, {
           "name": "cluster-name",
           "value": "${CLUSTER_NAME}"
        } ]
    }
    ```

    The script then obtains the report that includes all the attestation results (OS, Platform, Software trusted) and the ASSET_TAG with extended info for verification.

    Once all the worker nodes are registered with Intel Verification Server, we can start TSI deployment with attestation.

- TSI Attestation.

  1. The experiment with Intel has been done using Red Hat OpenShift, so in order to install TSI with Intel attestation, there are several configuration customization changes required to the [OpenShift script](./utils/install-open-shift.sh)
  1. Since Intel Attestation Server is using TPM device `/dev/tpm0` we need to switch TSI to use of `/dev/tpmrm0` that requires enablement of the TPM Proxy
  1. The standard Intel configuration enables TPM owner password for each individual TPM instance, and therefore is usually unique for each host – by default the Trust Agent randomly creates a new TPM ownership secret during installation when it takes ownership. However, for the purpose of the experiment, one can use the TPM_OWNER_SECRET variable in `trustagent.env` when installing the Trust Agent to specify a defined TPM password, instead of the default behavior of creating it randomly on each host. This way one can configure all hosts to use the same known TPM password, and that makes it easier to avoid TPM ownership clears and share the secret with other applications that need to use the TPM at that privilege level.
    - Get the password value by running the following command on every worker host:
     ```console
     tagent export-config --stdout | grep tpm.owner.secret
     ```
     The owner password format is HEX
  1. We also need Intel Attestation Server creds (ISecL authentication service credentials are configured in populate-users.env), same as the Asset Registration above.
  ```console
  export ISECL_USERNAME=
  export ISECL_PASSWD=
  ```
  1. Next are the ISecL endpoints that can be obtained by running `tagent export-config --stdout`:
  ```console
  export AUTH_ENDPOINT=(value of aas.api.url)
  export ISECL_ENDPOINT=(value of mtwilson.api.url)
  ```
  1.	Values for $CLUSTER_NAME and $REGION must match the values provided during Asset Registration with Intel Verification Server step.
  1. Code changes in [OpenShift script](./utils/install-open-shift.sh) script in ‘executeInstall-2’ section:
  ```console
    helm template ${HELM_REL_2}/ti-key-release-2/ --name tsi-2 \
    --set ti-key-release-1.vaultAddress=$VAULT_ADDR \
    --set ti-key-release-1.cluster.name=$CLUSTER_NAME \
    --set ti-key-release-1.cluster.region=$REGION \
    --set ti-key-release-1.runSidecar=$RUN_SIDECAR \
    --set jssService.tpm.interface_type=dev \
    --set jssService.tpm.device=/dev/tpmrm0 \
    --set jssService.tpm.owner_password=$TPM_PASSWD \
    --set jssService.tpm.owner_password_format=hex \
    --set jssService.attestion.kind=isecl \
    --set jssService.attestion.isecl.verificationService.tokenService=$AUTH_ENDPOINT \
    --set jssService.attestion.isecl.verificationService.service=$ISECL_ENDPOINT \
    --set jssService.attestion.isecl.verificationService.username=$ISECL_USERNAME \
    --set jssService.attestion.isecl.verificationService.password=$ISECL_PASSWD \
    --set jssService.type=vtpm2-server > ${INSTALL_FILE}
    ```
    As a result of these changes, TSI will be installed in the cluster, using an attestation report from the Intel Attestation Service to provide the identities of the workers and to keep the attestation going. Also, the TSI signing service would be using hardware TPM.

### Openshift
Installation of Trusted Service Identity on RedHat OpenShift requires several steps
to overcome the additional security restrictions. To make this process simpler,
we introduced a script to drive this installation ([utils/install-open-shift.sh](./utils/install-open-shift.sh))

Before we start, several considerations:
* The script is not using Helm to drive the installation, but instead, using Helm client it extracts  the relevant installation files and customize them as needed.
* The OpenShift installation requires OpenShift client `oc` installed and configured. Please follow the [oc documentation](https://docs.openshift.com/container-platform/4.2/cli_reference/openshift_cli/getting-started-cli.html) the `oc` cli can be obtained [here](https://mirror.openshift.com/pub/openshift-v4/clients/oc/4.3/)

OpenShift Installation:
* Setup the required parameters, either directly in the script ([utils/install-open-shift.sh](./utils/install-open-shift.sh)) or as env. variables
* When running on IKS, you can use the script to obtain cluster information: [utils/get-cluster-info.sh](./utils/get-cluster-info.sh)
* Required parameters:
  * CLUSTER_NAME - name of the cluster, e.g. CLUSTER_NAME="my-roks4"
  * REGION - label of the datacenter region e.g. CLUSTER_REGION="eu-de"
  * JSS_TYPE - TSI currently supports 2 JSS services,`vtpm2-server` or `jss-server` e.g. JSS_TYPE=vtpm2-server
* Optional parameters:
  - VAULT_ADDR - external access to your [Vault service](./README.md#setup-vault). If not specified,
install would create a Vault instance in `tsi-vault` namespace.
 - RUN_SIDECAR - `true/false` see the [Sidecar instructions](./README.md#sidecar)
* assuming the KUBECONFIG and `oc` are configured, execute the installation by running the script.
* To track the status of the installation, you can start another console pointing at the same OpenShift cluster, setup KUBECONFIG, then run:
  ```
    watch -n 5 kubectl -n trusted-identity get all
  ```
* Follow the installation instructions on your screen

### Setup Vault
TSI requires Vault to store the secrets. If you have a Vault instance that can be
used for this TSI installation, make sure you have admin privileges to access it.
Otherwise, follow the simple steps below to create a Vault instance, as a pod and
service, deployed in `tsi-vault` namespace in your cluster.

```console
kubectl create ns tsi-vault
kubectl -n tsi-vault create -f examples/vault/vault.yaml
service/tsi-vault created
deployment.apps/tsi-vault created
```

#### Obtain remote access to Vault service
For `minikube` obtain the current endpoint as follow
<details><summary>Click to view minikube steps</summary>

```console
minikube service tsi-vault -n tsi-vault --url
http://192.168.99.105:30229
# assign it to VAULT_ADDR env. variable:
export VAULT_ADDR=http://192.168.99.105:30229
```
</details>


To access Vault remotely in `IKS`, setup ingress access.
<details><summary>Click to view IKS steps</summary>

Obtain the ingress name using `ibmcloud` cli:
```console
$ # first obtain the cluster name:
$ ibmcloud ks clusters
$ # then use the cluster name to get the Ingress info:
$ ibmcloud ks cluster get --cluster <cluster_name> | grep Ingress
Ingress Subdomain:              tsi-kube01-9d995c4a8c7c5f281ce13xxxxxxxxxxx-0000.eu-de.containers.appdomain.cloud
Ingress Secret:                 tsi-kube01-9d995c4a8c7c5f281ce13xxxxxxxxxxx-0000
Ingress Status:                 healthy
Ingress Message:                All Ingress components are healthy
```
Build an ingress file from `example/vault/ingress.IKS.template.yaml`,
using the `Ingress Subdomain` information obtained above. You can use any arbitrary
prefix in addition to the Ingress value. For example:

`host: tsi-vault.my-tsi-cluster-9d995c4a8c7c5f281ce13xxxxxxxxxxx-0000.eu-de.containers.appdomain.cloud`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: vault-ingress
  namespace: tsi-vault
spec:
  rules:
  - host: tsi-vault.my-tsi-cluster-9d995c4a8c7c5f281ce13xxxxxxxxxxx-0000.eu-de.containers.appdomain.cloud
    http:
      paths:
      - pathType: Prefix
        path: "/"
        backend:
          service:
            name: tsi-vault
            port:
              number: 8200
```

create ingress:
```console
$ kubectl -n tsi-vault create -f ingress-IKS.yaml
```

Create VAULT_ADDR env. variable:
```console
export VAULT_ADDR="http://<Ingress>"
```
</details>

To access Vault remotely OpenShift (including IKS ROKS)
<details><summary>Click to view OpenShift steps</summary>

This assumes the OpenShift command line is already installed. Otherwise see
the [documentation](https://docs.openshift.com/container-platform/4.2/cli_reference/openshift_cli/getting-started-cli.html)
and you can get `oc` cli from https://mirror.openshift.com/pub/openshift-v4/clients/oc/4.3/

```console
oc -n tsi-vault expose svc/tsi-vault
export VAULT_ADDR="http://$(oc -n tsi-vault get route tsi-vault -o jsonpath='{.spec.host}')"
export ROOT_TOKEN=$(kubectl -n tsi-vault logs $(kubectl -n tsi-vault get po | grep tsi-vault-| awk '{print $1}') | grep Root | cut -d' ' -f3); echo "export ROOT_TOKEN=$ROOT_TOKEN"
```

</details>

Test the remote connection to vault:
```console
$ curl  http://<Ingress Subdomain or ICP master IP>/
<a href="/ui/">Temporary Redirect</a>.
```
At this point, this is an expected result.

Once the Vault service is running and `VAULT_ADDR` is defined, execute one-time
Vault setup:

```console
examples/vault/demo.vault-setup.sh $VAULT_ADDR tsi-vault
```

### Setup Cluster Nodes
The following information is required to deploy TSI node-setup helm chart:
* CLUSTER_NAME - name of the cluster. This must correspond to the actual name of the cluster
* REGION - label associated with the actual region for the data center (e.g. eu-de, us-south, eu-gb)
When using IKS, these values can be obtain via a script:

```console
. ./utils/get-cluster-info.sh
export CLUSTER_NAME=ti-test1
export REGION=eu-de
```
Then use the provided output to setup env. variables to be used later.

TSI currently supports 2 methods for signing JWT Tokens:
* using TPM2 - private keys are obtained directly from TPM using TPM wrapper (VTPM2)
* using custom signing service JSS (JWT Signing Service)

To use vTPM, deploy TSI Node Setup helm charts with all the functions disabled. The setup containers are needed only to register the nodes with Vault.

Replace X.X.X with a proper version numbers (typically the highest, the most recent).
```console
helm install charts/tsi-node-setup-vX.X.X.tgz --debug --name tsi-setup --set reset.all=false \
--set reset.x5c=false --set cluster.name=$CLUSTER_NAME --set cluster.region=$REGION
```

In order to run JSS server, all worker nodes have to be setup with private keys.  This operation needs to be executed only once.
If you are running this setup for the first time or like to override previous setup values, execute the helm command below.


```console
helm install charts/tsi-node-setup-vX.X.X.tgz --debug --name tsi-setup --set reset.all=true \
--set cluster.name=$CLUSTER_NAME --set cluster.region=$REGION
```

To keep the existing private key, but just reset the intermediate CA (`x5c`)
```console
helm install charts/tsi-node-setup-vX.X.X.tgz --debug --name tsi-setup --set reset.x5c=true \
--set cluster.name=$CLUSTER_NAME --set cluster.region=$REGION
```

Once the worker nodes are setup, deploy the TSI environment

### Sidecar
TSI sidecar runs along your application container, in the same pod, and it periodically
(`JWT_TTL_SEC`) creates JWT token that represents measured identity of the container.
Additionally, it retrieves secrets from Vault (using `SECRET_REFRESH_SEC` frequency) .
This model increases the security, by periodically validating the secrets that can
be modified or revoked. Revoked secret are removed from the application.
Secrets are mounted to the container using the `tsi.secret/local-path` path defined
in the application annotation during the container init period. Then, by default,
updated by the sidecar. It is possible to disable the sidecar, by setting:
`ti-key-release-1.runSidecar=false` in helm deployment chart or `RUN_SIDECAR="false"`
in [OpenShift install](utils/install-open-shift.sh) script.
As a result, the secrets would be assigned only once in the pod lifetime and they
cannot be changed or revoked without restarting the pod.
Disabling the sidecar supports Kubernetes Jobs, that change the state to Completed
when the container ends the transaction. Since sidecars are always running indefinitely,
job would never complete.

### Install Trusted Service Identity framework
Make sure all the [prerequisites](./README.md#prerequisites) are satisfied.

#### Deploy Helm charts
TSI helm charts are included with this repo under [charts/](./charts/) directory.
You can use them directly or use the charts that you built yourself (see instructions below).

The following information is required to deploy TSI helm charts:
* cluster name - name of the cluster. This must correspond to the actual name of the cluster
* region - label associated with the actual region for the data center (e.g. eu-de, us-south, wdc01)
* vault address - the remote address of the Vault service that contains the TSI secrets to be retrieved by the sidecar. Use the env. variable VAULT_ADDR set [above](./README.md#setup-vault)
* jss service - TSI currently support 2 mechanism for running the JSS (JWT Signing Service):
  - jss-server - custom service for signing JWT tokens (default)
  - vtpm2-server - JWT token signer using a software wrapper for TPM2
* debug - if set to true, allows creating test files (see [here](./CONTRIBUTING.md#testing-tsi))

Replace X.X.X with a proper version numbers (typically the highest, the most recent).

```console
export VAULT_ADDR=http://<vault_location>
helm install charts/ti-key-release-2-vX.X.X.tgz --debug --name tsi \
--set ti-key-release-1.cluster.name=$CLUSTER_NAME \
--set ti-key-release-1.cluster.region=$REGION \
--set ti-key-release-1.vaultAddress=$VAULT_ADDR \
--set jssService.type=jss-server
```
For example:
```console
export VAULT_ADDR=http://ti-test1.eu-de.containers.appdomain.cloud
helm install charts/ti-key-release-2-X.X.X.tgz --debug --name tsi \
--set ti-key-release-1.cluster.name=ti-fra02 \
--set ti-key-release-1.cluster.region=eu-de \
--set ti-key-release-1.vaultAddress=$VAULT_ADDR \
--set jssService.type=jss-server
```

Complete list of available setup parameters can be obtained as follow:
```console
helm inspect values charts/ti-key-release-2-X.X.X.tgz > config.yaml
# modify config.yaml
helm install -i --values=config.yaml tsi-install charts/ti-key-release-2-X.X.X.tgz
# or upgrade existing deployment
helm upgrade -i --values=config.yaml tsi-install charts/ti-key-release-2-X.X.X.tgz
```

### Boostrapping - CI/CD pipeline
The bootstrapping process is shown in details under the [Vault demo](examples/vault/README.md)

## Run Demo
For next steps, review [demo](examples/README.md) examples.

## Sample JWT claims
Once the TSI environment is operational, the application container will have
access to JWT Token. The token can be inspected in the JWT [Debugger](https://jwt.io/) in Encoded window.

Sample JWT Claims:
```json
{
  "cluster-name": "ti_demo",
  "region": "us-south",
  "exp": 1557170306,
  "iat": 1557170276,
  "images": "f36b6d491e0a62cb704aea74d65fabf1f7130832e9f32d0771de1d7c727a79cc",
  "images-names": "tsidentity/myubuntu@sha256:5b224e11f0e8daf35deb9aebc86218f1c444d2b88f89c57420a61b1b3c24584c",
  "iss": "wsched@us.ibm.com",
  "machineid": "fa967df1a948495596ad6ba5f665f340",
  "namespace": "trusted-identity",
  "pod": "myubuntu-698b749889-vvgts",
  "sub": "wsched@us.ibm.com"
}
```

### Cleanup
Remove all the resources created for Trusted Identity
```console
./utils/cleanup.sh
```
To start a fresh deployment, make sure to run `./utils/init-namespace.sh` again after the cleanup.

## Security Considerations
To improve security measures, we have decided to move all application containers
to a different namespace and keep all the TSI framework as _protected namespace_
that cannot host application and other containers (since version 1.4)

## Reporting security issues

Our [maintainers](./MAINTAINERS.md) take security seriously. If you discover a security
issue, please bring it to their attention right away!

Please DO NOT file a public issue, they will be removed; instead please reach out
to the maintainers privately.

Security reports are greatly appreciated, and Trusted Service Identity team will
publicly thank you for it.
