# Vault Plugin: JWT Auth Backend for Trusted Service Identity

This is a standalone backend plugin for use with [Hashicorp Vault](https://www.github.com/hashicorp/vault).
This plugin allows for JWTs (including OIDC tokens) to authenticate with Vault.

## Quick Links
    - Vault Website: https://www.vaultproject.io
    - JWT Auth Docs: https://www.vaultproject.io/docs/auth/jwt.html
    - Main Project Github: https://www.github.com/hashicorp/vault

This document provides guidance for plugin development.

## Plugin Development
### Getting Started

This is a [Vault plugin](https://www.vaultproject.io/docs/internals/plugins.html)
and is meant to work with Vault. This guide assumes you have already installed Vault
and have a basic understanding of how Vault works.

Otherwise, first read this guide on how to [get started with Vault](https://www.vaultproject.io/intro/getting-started/install.html).

To learn specifically about how plugins work, see documentation on [Vault plugins](https://www.vaultproject.io/docs/internals/plugins.html).

## Usage

Please see [documentation for the plugin](https://www.vaultproject.io/docs/auth/jwt.html)
on the Vault website.

This plugin is currently built into Vault and by default is accessed
at `auth/jwt`. To enable this in a running Vault server:

```sh
$ vault auth enable jwt
Successfully enabled 'jwt' at 'jwt'!
```

To see all the supported paths, see the [JWT auth backend docs](https://www.vaultproject.io/docs/auth/jwt.html).

## Developing the TSI plugin for Vault

If you wish to work on this plugin, you'll first need
[Go](https://www.golang.org) installed on your machine.

This component is the integral part of the Trusted Service Identity project, so
please refer to installation instruction in main [README](../../README.md#prerequisites) to clone the repository and setup [GOPATH](https://golang.org/doc/code.html#GOPATH).

Then you can then download any required build tools by bootstrapping your
environment:

```sh
$ make bootstrap
```

Setup dependencies (this builds `vendor` directory)

```sh
$ dep ensure
```

To compile a development version of this plugin, run `make` or `make dev`.
This will put the plugin binary in the `bin` and `$GOPATH/bin` folders. `dev`
mode will only generate the binary for your platform and is faster:

```sh
$ make
$ make dev
```

Or execute `make all` to compile, build docker image and push to the image repository.

```sh
$ make all
```
