# Trusted Identity

## Prerequisites

1. Make sure you have an IBM Cloud (formerly Bluemix) account and you have the [IBM Cloud CLI](https://console.bluemix.net/docs/cli/reference/bluemix_cli/get_started.html#getting-started) installed
2. Make sure you have a running kubernetes cluster, e.g.
[IBM Container service](https://console.bluemix.net/docs/containers/container_index.html#container_index) or [minikube](https://github.com/kubernetes/minikube) and that kubectl is configured to access that cluster. Test the access with
```console
kubectl get pods --all-namespaces
```

## Build and Install
Clone this project in a local directory, in your GOPATH

```console
cd $GOPATH
mkdir -p $GOPATH/src/github.ibm.com/kompass/
cd src/github.ibm.com/kompass/
git clone git@github.ibm.com:kompass/TI-KeyRelease.git
cd TI-KeyRelease
```
If you cannot clone the project with the git ssh protocol, make sure [you add your
ssh public key to your IBM GitHub Enterprise Account](https://help.github.com/enterprise/2.13/user/articles/adding-a-new-ssh-key-to-your-github-account/).

Execute `dep` to manage GoLang dependencies for this project.

On MacOS you can install or upgrade to the latest released version with Homebrew:

```console
brew install dep
brew upgrade dep
```

On other platforms you can use the install.sh script:

```
curl https://raw.githubusercontent.com/golang/dep/master/install.sh | sh
```

It will install into your $GOPATH/bin directory by default or any other directory you specify using the INSTALL_DIRECTORY environment variable.

To compile and build the image, get and test the dependencies:

```console
make dep get-deps test-deps
```
This might take some time to execute as it scans and installs the dependencies.
Once the dependencies are installed, execute the build.

```console
make build
```
Now you can create an docker image:

```console
make docker
```

In order to push the image to public Artifactory registry, you need to obtain an
access and create an [API key](https://pages.github.ibm.com/TAAS/tools_guide/artifactory/authentication/#authenticating-using-an-api-key). The repository name is `res-kompass-kompass-docker-local.artifactory.swg-devops.com`

Execute the docker login and push the image:

```console
docker login res-kompass-kompass-docker-local.artifactory.swg-devops.com
Username: <your-user-id>
Password: <API-key>

make docker-push
# or simply do it all at once:
make all
```

Compile and create images for other sub-components

```console
cd revorker
make all
cd ../gen-vault-cert
make all
```

To deploy manually:

```console
./deploy.sh
```

## Helm Deployment
The deployment is done in `trusted-identity` namespace. If you are testing or developing
the code and execute the deployment several time, it is a good idea to cleanup the namespace before executing another deployment. Run cleanup first, then init to initialize the namespace.
This would remove all the components and artifacts, then recreate a new, empty namespace:

```console
./cleanup.sh
./init-namespace.sh
```

Currently the images for Trusted Identity project are stored in Artifactory. In order to
use them, user has to be authenticated. You must obtain the [API key](https://pages.github.ibm.com/TAAS/tools_guide/artifactory/authentication/#authenticating-using-an-api-key)
as described above.

Create a secret that contains your Artifactory user id (e.g. user@ibm.com) and API key.
(This needs to be done every-time the new namespace is created)

```console
kubectl -n trusted-identity create secret docker-registry regcred \ --docker-server=res-kompass-kompass-docker-local.artifactory.swg-devops.com
--docker-username=user@ibm.com \
--docker-password=${API_KEY} \
--docker-email=user@ibm.com

# to check your secret:
kubectl -n trusted-identity get secret regcred --output="jsonpath={.data.\.dockerconfigjson}" | base64 --decode
```

Install [Helm](https://github.com/kubernetes/helm/blob/master/docs/install.md). On Mac OS X you can use brew to install helm:
```bash
  brew install kubernetes-helm
  helm init
```

Currently there are 2 charts to deploy TI KeyRelease: ti-key-release-1 and ti-key-rel
-2
Package the helm charts:
```console
cd TI-KeyRelease
helm package charts/ti-key-release-1
# update helm dependencies
helm dep update charts/ti-key-release-2
helm package --dependency-update charts/ti-key-release-2
```

The helm charts are ready to deploy

```console
helm install ti-key-release-2-0.1.0.tgz --debug --name ti-test
```


## Testing
Once environment deployed, execute a test by deploying the following file:
```console
kubectl -n trusted-identity create -f myubuntu_inject.yaml
```
