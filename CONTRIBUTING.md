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
To run a full build that compiles the code, builds images and creates helm packages, run the following:

```console
./buildTSI.sh
```

When pushing the images to the registry, the user has to be logged in to Docker Hub with permissions to push images to `hub.docker.com/repository/docker/trustedseriviceidentity`. Make sure you are part of the Organization: [https://hub.docker.com/orgs/trustedseriviceidentity](https://hub.docker.com/orgs/trustedseriviceidentity)

or if you like to build individual components:

```console
make build
```

Now you can create a docker image:

```console
make docker
```

If you have access to our registry, you can push your image now:

```console
make docker-push
```

Compile and create images for other sub-components

```console
make all -C components/jss/
make all -C components/jwt-sidecar/
make all -C components/node-setup/
```
vTPM is no longer a required component, but if you like to still use it, either version
vTPM v1 or v2, built them as shown below and then reference them accordingly in the
helm deployment.

```console
make all -C components/vtpm-server/
make all -C components/vtpm2-server/
```

Compile and build examples (JWT server and client)

```console
make all -C examples/vault-client/
make all -C examples/vault-plugin/
```

## TSI Helm Deployment
The deployment is done in `trusted-identity` namespace. If you are testing or
developing the code and execute the deployment several times, it is a good idea
to cleanup the namespace before executing another deployment.

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
