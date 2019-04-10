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
secret, then deploy TI.
The following information is required to deploy TI helm charts:
* cluster name - name of the cluster. This should correspond to actual name of the cluster
* cluster region - label associated with the actual region for the data center (e.g. eu-de, dal09, wdc01)
* ingress host - this is required to setup the vTPM service remotely, by CI/CD pipeline scripts. for example,
in IBM Cloud IKS, the ingress information can be obtained using  `ibmcloud ks cluster-get <cluster-name> | grep Ingress`
command. For ICP, set ingress enabled to false, keep the host empty and use IPs directly (typically master or proxy IP)

Example. Replace X.X.X with a proper version numbers.

```console
helm install ti-key-release-2-X.X.X.tgz --debug --name ti-test \
--set ti-key-release-1.cluster.name=ti-fra02 \
--set ti-key-release-1.cluster.region=eu-de \
--set ti-key-release-1.ingress.host=ti-fra02.eu-de.containers.appdomain.cloud
```

Once environment deployed, follow the output dynamically created by helm install:
Test if you can obtain CSR from vTPM:

```
Ingress allows a public access to vTPM CSR:
  curl http://ti-fra02.eu-de.containers.appdomain.cloud:/public/getCSR

$ curl http://ti-fra02.eu-de.containers.appdomain.cloud:/public/getCSR
  -----BEGIN CERTIFICATE REQUEST-----
  MIICYDCCAUgCAQAwGzEZMBcGA1UEAwwQdnRwbTItand0LXNlcnZlcjCCASIwDQYJ
  KoZIhvcNAQEBBQADggEPADCCAQoCggEBAK2ZiVYAALSs6HmJPUZDZosMS6qPaQwc
  . . . . . . . . . . . . . . . . . . .GUrDrCj7QnxyrYrgSiPu/xJvD+H
  8kW4q7nvsZm2VGKpeRpbQxj3ZlcZD2/Xm+WsKChU0wGk9qHt85qwGAzOgDfEo5Z5
  PgmLRl1PpyS3aVUBIpu8Xx+wsL5ZgVzUz1ScIi2qNPO7SqFU
  -----END CERTIFICATE REQUEST-----

Try to deploy a sample pod:

kubectl create -f examples/myubuntu.yaml -n trusted-identity
```
