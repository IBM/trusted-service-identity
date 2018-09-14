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

```console
dep ensure
```

This might take some time to execute as it scans and installs the dependencies.
Once the dependencies are installed, execute the build.

```console
./build
```
You will receive an error that you are denied write access to `lumjjb/ti-injector`
registry. This is expected. You can modify [build](./build) script and replace
`lumjjb` with your own registry namespace. If you change it, make sure you update
[myubuntu_inject.yaml](myubuntu_inject.yaml) and [gen-vault-cert/build](gen-vault-cert/build) scripts.


```console
cd gen-vault-cert/
./build

cd ..
./deploy.sh
```

## Helm Deployment

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
