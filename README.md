# Trusted Service Identity (TSI)

Trusted Service Identity is closing the gap of preventing access to secrets by
an untrusted operator during the process of obtaining authorization for data
access by the applications running in the public cloud.

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
  - [Setup Cluster](./README.md#setup-cluster)
  - [Install](./README.md#install-trusted-service-identity-framework)
  - [Test](./README.md#testing-deployment)
  - [Cleanup](./README.md#cleanup)
- [Usage (demo)](examples/README.md)
- [Integrating TIS with your Application (Vault example)](examples/README-AppDeveloperVault.md)
- [Integrating TIS with your Application (Key Store example)](examples/README-AppDeveloperKeyServer.md)
- [Contributing (TIS Development)](./CONTRIBUTING.md)
- Extras
  - [Automated Vault Certificate Management](./CONTRIBUTING.md#automate-vault-certificates)

## Installation
### Prerequisites
#### Clone this project in a local directory, in your GOPATH
```console
cd $GOPATH
mkdir -p $GOPATH/src/github.ibm.com/kompass/
cd src/github.ibm.com/kompass/
git clone git@github.ibm.com:kompass/TI-KeyRelease.git
cd TI-KeyRelease
```
If you cannot clone the project with the git ssh protocol, make sure [you add your
ssh public key to your IBM GitHub Enterprise Account](https://help.github.com/enterprise/2.13/user/articles/adding-a-new-ssh-key-to-your-github-account/).

#### Kubernetes cluster
* Trusted Service Identity requires Kuberenetes cluster. You can use [IBM Cloud Kubernetes Service](www.ibm.com/Kubernetes/Service‎),
[IBM Cloud Private](https://www.ibm.com/cloud/private), [Openshift](https://docs.openshift.com/container-platform/3.3/install_config/install/quick_install.html) or [minikube](https://github.com/kubernetes/minikube)
* Make sure the Kuberenetes cluster is operational and you can access it remotely using [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) tool
* Make sure the `KUBECONFIG` is properly set and you can access the cluster. Test the access with
```console
export KUBECONFIG=<location of your kubernetes config. files, as per documentation for your cluster>
kubectl get pods --all-namespaces
```

#### Setup kubectl alias
Through out this whole project we will be working with this newly created namespace.
Let's setup an alias `kk` to make typing faster:
```console
$ alias kk="kubectl -n trusted-identity"
$ # list all the pods to test it
$ kk get po
```

#### Install and initialize Helm environment
This project requires Helm v2.10.0 or higher.
Install [Helm](https://github.com/kubernetes/helm/blob/master/docs/install.md). On Mac OS X you can use brew to install helm:
```bash
  brew install kubernetes-helm
  # or to upgrade the existing helm
  brew upgrade kubernetes-helm
  # then initialize (assuming your KUBECONFIG for the current cluster is already setup)
  helm init
```
*NOTE*: If you are using IBM Cloud Kuberenetes Service, with K8s version 1.12 or higher,
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

#### Setup access to installation images
Currently the images for Trusted Identity project are stored in Artifactory. In order to
use them, user has to be authenticated. You must obtain the [API key](https://pages.github.ibm.com/TAAS/tools_guide/artifactory/authentication/#authenticating-using-an-api-key)
as described here. Simply generate one [here](https://na.artifactory.swg-devops.com/artifactory/webapp/#/profile).

Create a secret that contains your Artifactory user id (e.g. user@ibm.com) and API key.
(This needs to be done every-time the new namespace is created)
```console
$ kk create secret docker-registry regcred \
--docker-server=res-kompass-kompass-docker-local.artifactory.swg-devops.com \
--docker-username=user@ibm.com \
--docker-password=${API_KEY} \
--docker-email=user@ibm.com

$ # to check your secret:
$ kk get secret regcred --output="jsonpath={.data.\.dockerconfigjson}" | base64 --decode
```

or update the [init-namespace.sh](./init-namespace.sh) script.

The deployment is done in `trusted-identity` namespace. If you are testing or developing
the code and execute the deployment several times, it is a good idea to cleanup
the namespace before executing another deployment. Run cleanup first, then init
to initialize the namespace.This would remove all the components and artifacts.

Then recreate a new, empty namespace:

```console
./cleanup.sh
./init-namespace.sh
```

### Setup Cluster
In order to install and run Trusted Service Identity, all worker nodes have to be
setup with a private key, either directly or through vTPM (virtual Trusted Platform Module).
This operation needs to be executed only once.

If you are running this for the first time or like to override previous setup values:
```console
helm install charts/tsi-node-setup --debug --name tsi-setup --set reset.all=true
```

To keep the existing private key, but just reset the intermediate CA (`x5c`)
```console
helm install charts/tsi-node-setup --debug --name tsi-setup --set reset.x5c=true
```

Once the worker nodes are setup, deploy the TSI environment


### Install Trusted Service Identity framework
Make sure all the [prerequisites](./README.md#prerequisites) are satisfied.

#### Deploy Helm charts
TI helm charts are included with this repo under [charts/](./charts/) directory.
You can use them directly or use the charts that you built yourself (see instructions below).

The following information is required to deploy TSI helm charts:
* cluster name - name of the cluster. This should correspond to actual name of the cluster
* cluster region - label associated with the actual region for the data center (e.g. eu-de, dal09, wdc01)

Replace X.X.X with a proper version numbers (typically the highest, the most recent).

```console
helm install charts/ti-key-release-2-X.X.X.tgz --debug --name ti-test \
--set ti-key-release-1.cluster.name=CLUSTER_NAME \
--set ti-key-release-1.cluster.region=CLUSTER_REGION
```
For example:
```console
helm install charts/ti-key-release-2-X.X.X.tgz --debug --name ti-test \
--set ti-key-release-1.cluster.name=ti-fra02 \
--set ti-key-release-1.cluster.region=eu-de
```

Complete list of available setup parameters can be obtained as follow:
```console
helm inspect values charts/ti-key-release-2-X.X.X.tgz > config.yaml
# modify config.yaml
helm install -i --values=config.yaml ti-test charts/ti-key-release-2-X.X.X.tgz
# or upgrade existing deployment
helm upgrade -i --values=config.yaml ti-test charts/ti-key-release-2-X.X.X.tgz
```

### Boostrapping - CI/CD pipeline
The bootstrapping process is shown in details under the [Vault demo](examples/README.md)

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
  "images-names": "res-kompass-kompass-docker-local.artifactory.swg-devops.com/myubuntu:latest@sha256:5b224e11f0e8daf35deb9aebc86218f1c444d2b88f89c57420a61b1b3c24584c",
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
To start a fresh deployment, make sure to run `./init.sh` again after the cleanup.
