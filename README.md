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

#### Setup access to installation images
Currently the images for Trusted Identity project are stored in Artifactory. In order to
use them, user has to be authenticated. You must obtain the [API key](https://pages.github.ibm.com/TAAS/tools_guide/artifactory/authentication/#authenticating-using-an-api-key)
as described here. Simply generate one [here](https://na.artifactory.swg-devops.com/artifactory/webapp/#/profile)
Create a secret that contains your Artifactory user id (e.g. user@ibm.com) and API key.
(This needs to be done every-time the new namespace is created)
```console
kubectl -n trusted-identity create secret docker-registry regcred \
--docker-server=res-kompass-kompass-docker-local.artifactory.swg-devops.com \
--docker-username=user@ibm.com \
--docker-password=${API_KEY} \
--docker-email=user@ibm.com

# to check your secret:
kubectl -n trusted-identity get secret regcred --output="jsonpath={.data.\.dockerconfigjson}" | base64 --decode
```

or update the [init-namespace.sh](./init-namespace.sh) script.

The deployment is done in `trusted-identity` namespace. If you are testing or developing
the code and execute the deployment several time, it is a good idea to cleanup the namespace before executing another deployment. Run cleanup first, then init to initialize the namespace.

This would remove all the components and artifacts, then recreate a new, empty namespace:

```console
./cleanup.sh
./init-namespace.sh
```

### Install Trusted Service Identity framework
Make sure all the [prerequisites](./README.md#prerequisites) are satisfied.

#### Deploy Helm charts
TI helm charts are included with this repo under [charts/](./charts/) directory.
You can use them directly or use the charts that you created (see instructions below).

The following information is required to deploy TI helm charts:
* cluster name - name of the cluster. This should correspond to actual name of the cluster
* cluster region - label associated with the actual region for the data center (e.g. eu-de, dal09, wdc01)
* ingress host - this is required to setup the vTPM service remotely, by CI/CD pipeline scripts. for example,
in IBM Cloud IKS, the ingress information can be obtained using  `ibmcloud ks cluster-get <cluster-name> | grep Ingress`
command. For ICP, set ingress enabled to false, keep the host empty and use IPs directly (typically master or proxy IP)

*NOTE*: If you are using IBM Cloud Kuberenetes Service, with K8s version 1.12 or higher,
the kube-system default service account no longer has cluster-admin access to the Kubernetes API.
Running the helm install there might cause a following error:
```
Error: customresourcedefinitions.apiextensions.k8s.io "clustertis.trusted.identity" is forbidden: User "system:serviceaccount:kube-system:default" cannot delete resource "customresourcedefinitions" in API group "apiextensions.k8s.io" at the cluster scope
```

As a quick fix you can do a following (see [this](https://cloud.ibm.com/docs/containers?topic=containers-cs_versions#112_before) for more details):

```console
kubectl create clusterrolebinding kube-system:default --clusterrole=cluster-admin --serviceaccount=kube-system:default
```

Replace X.X.X with a proper version numbers (typically the highest, the most recent).

```console
helm install charts/ti-key-release-2-X.X.X.tgz --debug --name ti-test \
--set ti-key-release-1.cluster.name=ti-fra02 \
--set ti-key-release-1.cluster.region=eu-de \
--set ti-key-release-1.ingress.host=ti-fra02.eu-de.containers.appdomain.cloud
```

Complete list of available setup parameters can be obtained as follow:
```console
helm inspect values charts/ti-key-release-2-X.X.X.tgz > config.yaml
# modify config.yaml
helm install -i --values=config.yaml ti-test charts/ti-key-release-2-X.X.X.tgz
# or upgrade existing deployment
helm upgrade -i --values=config.yaml ti-test charts/ti-key-release-2-X.X.X.tgz
```

### Testing Deployment
Once environment deployed, follow the output dynamically created by helm install:

For example:

```
Ingress allows a public access to vTPM CSR:
  curl http://ti-fra02.eu-de.containers.appdomain.cloud/public/getCSR

```

```console
$ curl http://ti-fra02.eu-de.containers.appdomain.cloud/public/getCSR
  -----BEGIN CERTIFICATE REQUEST-----
  MIICYDCCAUgCAQAwGzEZMBcGA1UEAwwQdnRwbTItand0LXNlcnZlcjCCASIwDQYJ
  KoZIhvcNAQEBBQADggEPADCCAQoCggEBAK2ZiVYAALSs6HmJPUZDZosMS6qPaQwc
  . . . . . . . . . . . . . . . . . . .GUrDrCj7QnxyrYrgSiPu/xJvD+H
  8kW4q7nvsZm2VGKpeRpbQxj3ZlcZD2/Xm+WsKChU0wGk9qHt85qwGAzOgDfEo5Z5
  PgmLRl1PpyS3aVUBIpu8Xx+wsL5ZgVzUz1ScIi2qNPO7SqFU
  -----END CERTIFICATE REQUEST-----

Execute test:
    kubectl create -f examples/myubuntu.yaml -n trusted-identity
    kubectl -n trusted-identity create -f examples/myubuntu.yaml
    kubectl -n trusted-identity get pods
    kubectl -n trusted-identity exec -it myubuntu-xxx cat /jwt-tokens/token
```

#### Sample JWT claims
One can inspect the content of the token by simply pasting its content into
[Debugger](https://jwt.io/) in Encoded window.

```json
{
  "cluster-name": "ti_demo",
  "cluster-region": "dal09",
  "exp": 1557170306,
  "iat": 1557170276,
  "images": "f36b6d491e0a62cb704aea74d65fabf1f7130832e9f32d0771de1d7c727a79cc",
  "iss": "wsched@us.ibm.com",
  "machineid": "fa967df1a948495596ad6ba5f665f340",
  "namespace": "trusted-identity",
  "pod": "myubuntu-698b749889-vvgts",
  "sub": "wsched@us.ibm.com"
}
```

#### Run Sample Demo
Trusted Identity is ready for [a demo](examples/README.md)

### Cleanup
Remove all the resources created for Trusted Identity
```console
./cleanup.sh
```
Make sure to run `./init.sh` again after the cleanup to start the fresh deployment
