# Trusted Identity Examples - Demo
To demonstrate the capabilities of Trusted Identity, we prepared several examples:
* demo using **Vault with auth plugin** - this demo stands up a Vault server instance,
populates it with sample policies and secrets, then shows how the application retrieves
the secrets using Vault client
* demo using **Custom Key Manager** - this demo stands up a custom key manager server,
populates it with sample policies and secrets, then shows how the sample application
retrieves the secrets.

For a guidance how to create a custom application that is using Trusted Identity
* with Vault - refer to [Application Developer Guide](./README-AppDeveloperVault.md)
* with Key Server - refer to [Application Developer Guide](./README-AppDeveloperKeyServer.md)

## Demo with Vault
Before executing the demo, make sure all the [TI Prerequisites](../README.md#prerequisites)
are met and the [Trusted Service Identity framework](../README.md#install-trusted-service-identity-framework) is installed

[Vault Plugin Demo](./vault/README.md) components:
* bootstrapping the cluster (initialize the Vault and register JSS services)
* [vault](./vault) - authentication plugin extension to Hashicorp Vault
* [vault-client](./vault-client) - sample client that demonstrates how to retrieve
secrets from Vault

[Application Developer Guide](./README-AppDeveloperVault.md) to use with Vault.


## Demo with Key Manager
Before executing the demo, make sure all the [TI Prerequisites](../README.md#prerequisites)
are met and the [Trusted Service Identity framework](../README.md#install-trusted-service-identity-framework) is installed

[Simple Key Store Demo](./jwt-server/README.md) components:
* [jwt-server](./jwt-server) - simple key server that stores access keys to
Cloudant
* [jwt-client](./jwt-client) - sample code that calls `jwt-server` with JWT token
to obtain keys to Cloudant.

This demo sets up Key Server and sample JWT Cloudant client to demonstrate
how sample application can retrieve data securely from the Key Server using
Trusted Identity.

[Application Developer Guide](./README-AppDeveloperKeyServer.md) to use with Key Server.
