# Trusted Identity Examples - Demo
To demonstrate the capabilities of Trusted Identity, we prepared several examples:
* demo using [Vault with auth plugin](./REAMDE.md#demo-with-vault) - this demo
stands up a Vault server instance, populates it with sample policies and secrets,
then shows how the application retrieves the secrets using Vault client
* demo using [Custom Key Manager](./REAMDE.md#demo-with-key-manager) - this demo
stands up a custom key manager server, populates it with sample policies and secrets,
then shows how the sample application retrieves the secrets.

For a guidance how to create a custom application that is using Trusted Identity
please refer to [Application Developer Guide](./README-AppDeveloper.md)

## Demo with Vault
Before executing the demo, make sure all the [TI Prerequisites](../README.md#prerequisites)
are met and the [Trusted Service Identity framework](../REAMDE.md#install-trusted-service-identity-framework) is installed

Demo components:
* [vault-plugin](./vault-plugin) - authentication plugin extension to Hashicorp Vault
* [vault-client](./vault-client) - sample client that demonstrates how to retrieve
secrets from Vault

Please follow the [Vault Plugin demo](./vault-plugin/README.md) steps.

## Demo with Key Manager
Before executing the demo, make sure all the [TI Prerequisites](../README.md#prerequisites)
are met and the [Trusted Service Identity framework](../REAMDE.md#install-trusted-service-identity-framework) is installed

Demo components:
* [jwt-server](./jwt-server) - simple key server that stores access keys to
Cloudant
* [jwt-client](./jwt-client) - sample code that calls `jwt-server` with JWT token
to obtain keys to Cloudant.

This demo sets up Key Server and sample JWT Cloudant client to demonstrate
how sample application can retrieve data securely from the Key Server using
Trusted Identity.

Please follow the [Simple Key Store Demo](./jwt-server/README.md) steps.
