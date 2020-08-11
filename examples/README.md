# Trusted Identity Examples - Demo
To demonstrate the capabilities of Trusted Identity, we prepared several examples:
* demo using **Vault with auth plugin** - this demo stands up a Vault server instance,
populates it with sample policies and secrets, then shows how the application retrieves
the secrets using Vault client

For a guidance how to create a custom application that is using Trusted Identity
* with Vault - refer to [Application Developer Guide](./README-AppDeveloperVault.md)

## Demo with Vault
Before executing the demo, make sure all the [TI Prerequisites](../README.md#prerequisites)
are met and the [Trusted Service Identity framework](../README.md#install-trusted-service-identity-framework) is installed

[Vault Plugin Demo](./vault/README.md) components:
* bootstrapping the cluster (initialize the Vault and register JSS services)
* [vault-plugin](../components/vault-plugin/) - authentication plugin extension to Hashicorp Vault
* [vault-client](./vault-client) - sample client that demonstrates how to retrieve
secrets from Vault
* [vault-plugin development](../components/vault-plugin/README.md) - documentation on Vault plugin development

[Application Developer Guide](./README-AppDeveloperVault.md) to use with Vault.
