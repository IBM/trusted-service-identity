# Trusted Identity Examples - Demo
To demonstrate the capabilities of Trusted Identity we prepared several examples:
* [vault-plugin](./vault-plugin) - plugin extension to Hashicorp Vault
* [vault-client](./vault-client) - sample client that demonstrates how to retrieve
secrets from Vault
* [jwt-server](./jwt-server) - simple key server that stores access keys to
Cloudant
* [jwt-client](./jwt-client) - sample code that calls `jwt-server` with JWT token
to obtain keys to Cloudant.

For a guidance how to create a custom application that is using Trusted Identity
see the following [Application Developer Guide](./README-AppDeveloper.md)

This demo sets up Key Server and sample JWT Cloudant client to demonstrate
how sample application can retrieve data securely from the Key Server using
Trusted Identity.

[Vault Plugin demo](./vault-plugin/README.md) steps:
* Prerequisites
* Deploy TI framework
* Deploy Vault Server with plugin
* Deploy Vault Client
* For each cluster register JWKS/Pems from all the user nodes (vTPM deployment).
* Define sample policies and roles
* Execute sample transactions


[Simple Key Store Demo](./jwt-server/README.md) steps:
* Prerequisites
* Deploy TI framework
* Deploy Key Server
* Deploy JWT Cloudant client
* Install JWKS keys for each vTPM deployment  
* Define sample policies
* Execute sample transactions


## Prerequisites

1. Make sure the all the [TI Prerequisites](../README.md#prerequisites) are met.
2. Images are already built and published in artifactory, although if you like to
create your own images, follow the steps to [build](../README.md#build-and-install)
3. Make sure you have [Helm installed](../README.md#install-and-initialize-helm-environment)


## Deploy TI framework
Follow the [steps](../README.md#ti-key-release-helm-deployment) to setup `regcred`
secret, then deploy TI. Make sure to specify a cluster name and region.

Example:

```console
helm install charts/ti-key-release-2-X.X.X.tgz --debug --name ti-demo \
--set ti-key-release-1.cluster.name=EUcluster \
--set ti-key-release-1.cluster.region=eu-de
```

Once successful, try to deploy a sample pod:

```console
kubectl create -f examples/myubuntu.yaml -n trusted-identity
```
