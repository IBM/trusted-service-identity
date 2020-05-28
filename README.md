# Trusted Service Identity (TSI)

Trusted Service Identity by IBM Research is closing the gap of preventing access
to secrets by an untrusted operator during the process of obtaining authorization
for data access by the applications running in the public cloud.

The project ties Key Management Service technologies with identity via host
provenance and integrity.

TI limits access to keys (credentials, secrets) for service provider administrators,
by creating a key/credential release system based on authorization of container
workloads. Each application that requires access to key gets a short-term identity
in form of a JSON Web Token (JWT) as a digital biometric identity that is bound
to the process and signed by a chain of trust that originates from
physical hardware. Secrets are released to the application based on this identity.

## Table of Contents
- [Installation](./README.md#installation)
  - [Prerequisites](./README.md#prerequisites)
  - [Openshift](./README.md#openshift)
  - [Setup Vault](./README.md#setup-vault)
  - [Setup Cluster](./README.md#setup-cluster-nodes)
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
* Trusted Service Identity requires Kuberenetes cluster. You can use [IBM Cloud Kubernetes Service](https://www.ibm.com/cloud/container-service/),
[IBM Cloud Private](https://www.ibm.com/cloud/private), [Openshift](https://docs.openshift.com/container-platform/3.3/install_config/install/quick_install.html) or [minikube](https://github.com/kubernetes/minikube) or any other solution that provides Kubernetes cluster.
* Make sure the Kubernetes cluster is operational and you can access it remotely using [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) tool
* Make sure the `KUBECONFIG` is properly set and you can access the cluster. Test the access with
```console
export KUBECONFIG=<location of your kubernetes configuration files, as per documentation for your cluster>
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
The images are publicly available from Docker hub. For example, [https://hub.docker.com/repository/docker/trustedseriviceidentity/ti-webhook](https://hub.docker.com/repository/docker/trustedseriviceidentity/ti-webhook)

The deployment is done in `trusted-identity` namespace. If you are testing
or developing the code and execute the deployment several times, it is a good
idea to cleanup the namespace before executing another deployment. Run cleanup
first, then init to initialize the namespace.
This would remove all the components and artifacts.

Then recreate a new, empty namespace:

```console
./cleanup.sh
./init-namespace.sh
```

### Openshift
Installation of Trusted Service Identity on RedHat OpenShift requires several steps
to overcome the additional security restrictions. To make this process simpler,
we introduced a script to drive this installation ([install-open-shift.sh](./install-open-shift.sh))

Before we start, several considerations:
* The script is not using Helm to drive the installation, but instead, using Helm client it extracts  the relevant installation files and customize them as needed.
* Vault Service cannot be installed in the same OpenShift cluster, so instead we suggest starting the Vault service in another cluster, e.g. [IBM Kubernetes Service](https://www.ibm.com/cloud/container-service/). The Vault installation steps are specified [here](./README.md#setup-vault)
* Once the Vault Service is operational, the external access point to it is needed to complete the setup
* The OpenShift installation requires OpenShift client `oc` installed and configured. Please follow the [oc documentation](https://docs.openshift.com/container-platform/4.2/cli_reference/openshift_cli/getting-started-cli.html) the `oc` cli can be obtained [here](https://mirror.openshift.com/pub/openshift-v4/clients/oc/4.3/)

OpenShift Installation:
* Edit [install-open-shift.sh](./install-open-shift.sh) file by assigning the required parameters:
  * VAULT_ADDR - external access to your Vault service e.g. VAULT_ADDR=http://ti-test1.eu-de.containers.appdomain.cloud
  * CLUSTER_NAME - name of the cluster, e.g. CLUSTER_NAME="my-roks4"
  * CLUSTER_REGION - label of the datacenter region e.g. CLUSTER_REGION="eu-de"
  * JSS_TYPE - TSI currently supports 2 JSS services,`vtpm2-server` or `jss-server` e.g. JSS_TYPE=vtpm2-server
* assuming the KUBECONFIG and `oc` are configured, execute the installation by running the script.
* To track the status of the installation, you can start another console pointing at the same OpenShift cluster, setup KUBECONFIG, then run:
  ```
    watch -n 5 kubectl -n trusted-identity get all
  ```
* Follow the installation steps on your screen

### Setup Vault
TSI requires Vault to store the secrets. If you have a Vault instance that can be
used for this TSI installation, make sure you have admin privileges to access it.
Otherwise, follow the simple steps below to create a Vault instance, as a pod and
service, deployed in `trusted-identity` namespace in your cluster.

```console
kk create -f examples/vault/vault.yaml
service/tsi-vault created
deployment.apps/tsi-vault created
```

#### Obtain remote access to Vault service
For `minikube` obtain the current endpoint as follow
<details><summary>Click to view minikube steps</summary>

```console
minikube service tsi-vault -n trusted-identity --url
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
$ ibmcloud ks cluster-get <cluster_name> | grep Ingress
```
Build an ingress file from `example/vault/ingress-IKS.template.yaml`,
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
          serviceName: tsi-vault
          servicePort: 8200
        path: /
```

create ingress:
```console
$ kk create -f ingress-IKS.yaml
```
</details>


Test the remote connection to vault:
```console
$ curl  http://<Ingress Subdomain or ICP master IP>/
<a href="/ui/">Temporary Redirect</a>.
```
At this point, this is an expected result.

### Setup Cluster Nodes
The following information is required to deploy TSI node-setup helm chart:
* cluster name - name of the cluster. This must correspond to the actual name of the cluster
* cluster region - label associated with the actual region for the data center (e.g. eu-de, dal09, wdc01)
TSI currently supports 2 methods for signing JWT Tokens:
* using TPM2 - private keys are obtained directly from TPM using TPM wrapper (VTPM2)
* using custom signing service JSS (JWT Signing Service)

To use vTPM, deploy TSI Node Setup helm charts with all the functions disabled. The setup containers are needed only to register the nodes with Vault.

Replace X.X.X with a proper version numbers (typically the highest, the most recent).
```console
helm install charts/tsi-node-setup-X.X.X --debug --name tsi-setup --set reset.all=false \
--set reset.x5c=false --set cluster.name=CLUSTER_NAME --set cluster.region=CLUSTER_REGION
```

In order to run JSS server, all worker nodes have to be setup with private keys.  This operation needs to be executed only once.
If you are running this setup for the first time or like to override previous setup values, execute the helm command below.



```console
helm install charts/tsi-node-setup-X.X.X --debug --name tsi-setup --set reset.all=true \
--set cluster.name=CLUSTER_NAME --set cluster.region=CLUSTER_REGION
```

To keep the existing private key, but just reset the intermediate CA (`x5c`)
```console
helm install charts/tsi-node-setup-X.X.X --debug --name tsi-setup --set reset.x5c=true \
--set cluster.name=CLUSTER_NAME --set cluster.region=CLUSTER_REGION
```

Once the worker nodes are setup, deploy the TSI environment


### Install Trusted Service Identity framework
Make sure all the [prerequisites](./README.md#prerequisites) are satisfied.

#### Deploy Helm charts
TI helm charts are included with this repo under [charts/](./charts/) directory.
You can use them directly or use the charts that you built yourself (see instructions below).

The following information is required to deploy TSI helm charts:
* cluster name - name of the cluster. This must correspond to the actual name of the cluster
* cluster region - label associated with the actual region for the data center (e.g. eu-de, dal09, wdc01)
* vault address - the remote address of the Vault service that contains the TSI secrets to be retrieved by the sidecar. Use the env. variable VAULT_ADDR set [above](./README.md#setup-vault)
* jss service - TSI currently support 2 mechanism for running the JSS (JWT Signing Service):
  - jss-server - custom service for signing JWT tokens (default)
  - vtpm2-server - JWT token signer using a software wrapper for TPM2


Replace X.X.X with a proper version numbers (typically the highest, the most recent).

```console
export VAULT_ADDR=http://<vault_location>
helm install charts/ti-key-release-2-X.X.X.tgz --debug --name tsi \
--set ti-key-release-1.cluster.name=CLUSTER_NAME \
--set ti-key-release-1.cluster.region=CLUSTER_REGION \
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
  "cluster-region": "dal09",
  "exp": 1557170306,
  "iat": 1557170276,
  "images": "f36b6d491e0a62cb704aea74d65fabf1f7130832e9f32d0771de1d7c727a79cc",
  "images-names": "trustedseriviceidentity/myubuntu@sha256:5b224e11f0e8daf35deb9aebc86218f1c444d2b88f89c57420a61b1b3c24584c",
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
./cleanup.sh
```
To start a fresh deployment, make sure to run `./init-namespace.sh` again after the cleanup.

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
