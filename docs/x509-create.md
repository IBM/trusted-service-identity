# Instructions of Minting Certificates for x509 Proof of Possession
Instructions for generating x509 certificates use with
`x509pop` NodeAttestor.

The sample keys are present in [../sample-x509](../sample-x509) directory.
You can create a new set of certs and keys:
* [using a script](#generate_keys_using_a_script)
* [manually (recommended)](#generate_keys_manually)

## Generate keys using a script
The script for generating keys is based on:
https://github.com/spiffe/spire/blob/v1.2.0/test/fixture/nodeattestor/x509pop/generate.go

To create new sample certs and keys:
```console
cd ../sample-x509
go run generate.go
cd ..
```

## Generate keys manually
These are manual instructions for generating certs and keys
based on https://jamielinux.com/docs/openssl-certificate-authority/create-the-intermediate-pair.html

The steps are following:
* generate RootCA
* generate intermediate key and cert
* create node specific key and certificate signed with the intermediate key
* create node and intermediate certificate bundle used by NodeAttestor

### Generating RootCA

This example comes with sample x509 certificates and keys to demonstrate
`x509pop` nodeAttestor capabilities.

The sample keys are present in [../sample-x509](../sample-x509) directory.
You can create a new set of certs and keys:
* [using a script](#generate_keys_using_a_script)
* [manually (recommended)](#generate_keys_manually)

## Generate keys using a script
To create new sample certs and keys:
```console
mkdir x509/ca
cd x509/ca
mkdir certs crl newcerts private
chmod 700 private
touch index.txt
echo 1000 > serial
```
Create `ca/openssl.cnf`. Use [this](https://jamielinux.com/docs/openssl-certificate-authority/appendix/root-configuration-file.html) as a template.
Replace `dir` with the actual value.

Create RootCA Key:

```console
openssl genrsa -out private/ca.key.pem 4096
chmod 400 private/ca.key.pem
```

Create root certificate, provide *Common Name* e.g. `MyOrg Root CA`:

```console
openssl req -config openssl.cnf \
      -key private/ca.key.pem \
      -new -x509 -days 7300 -sha256 -extensions v3_ca \
      -out certs/ca.cert.pem
chmod 444 certs/ca.cert.pem
```

Verify the root certificate
```console
openssl x509 -noout -text -in certs/ca.cert.pem
```

### Create Intermediate CA

Add a `crlnumber` file to the intermediate CA directory tree.
It is used to keep track of certificate revocation lists.

```console
mkdir x509/ca/intermediate
cd x509/ca/intermediate
mkdir certs crl csr newcerts private
chmod 700 private
touch index.txt
echo 1000 > serial
echo 1000 > crlnumber
```

Create `ca/intermediate/openssl.cnf` file based on
[this](https://jamielinux.com/docs/openssl-certificate-authority/appendix/intermediate-configuration-file.html)
template. Make sure correct `dir` is used.

Create the intermediate key:

```console
openssl genrsa -out intermediate/private/intermediate.key.pem 4096
chmod 400 intermediate/private/intermediate.key.pem
```

Create the intermediate certificate:

Use the intermediate key to create a certificate signing request (CSR).
The details should generally match the root CA.
The Common Name, however, must be different.

```console
openssl req -config intermediate/openssl.cnf -new -sha256 \
      -key intermediate/private/intermediate.key.pem \
      -out intermediate/csr/intermediate.csr.pem
```

Create intermediate certificate:
```console
openssl ca -batch -config openssl.cnf -extensions v3_intermediate_ca \
      -days 3650 -notext -md sha256 \
      -in intermediate/csr/intermediate.csr.pem \
      -out intermediate/certs/intermediate.cert.pem

chmod 444 intermediate/certs/intermediate.cert.pem
```

Verify Intermediate CA:
```console
openssl verify -CAfile certs/ca.cert.pem \
      intermediate/certs/intermediate.cert.pem
```

`intermediate.cert.pem: OK`

To verify the node certs manually, create `cert-chain`.
Not needed for SPIRE Agent attestation.
```console
cat intermediate/certs/intermediate.cert.pem \
      certs/ca.cert.pem > intermediate/certs/ca-chain.cert.pem
chmod 444 intermediate/certs/ca-chain.cert.pem
```

### Sign Node Certificates
Create a private node key:

```console
cd x509/ca/
openssl genrsa -out intermediate/private/node.key.pem 2048
chmod 400 intermediate/private/node.key.pem
```

The steps below are from your perspective as the certificate authority.
A third-party, however, can instead create their own
private key and certificate signing request (CSR)
without revealing their private key to you.
In such case proceed signing with their CSR.

Create Node Certificate.
Make sure to use different `common name` for each node.

```console
openssl req -config intermediate/openssl.cnf \
      -key intermediate/private/node.key.pem \
      -new -sha256 -out intermediate/csr/node.csr.pem
```

Create Node certificate using CSR:
```console
openssl ca -batch -config intermediate/openssl.cnf \
      -extensions server_cert -days 375 -notext -md sha256 \
      -in intermediate/csr/node.csr.pem \
      -out intermediate/certs/node.cert.pem
chmod 444 intermediate/certs/node.cert.pem
```

Use the CA certificate chain file we created earlier (ca-chain.cert.pem)
to verify that the new certificate has a valid chain of trust.

```console
openssl verify -CAfile intermediate/certs/ca-chain.cert.pem \
      intermediate/certs/node.cert.pem
```
`node.cert.pem: OK`


Create node bundle needed for SPIRE Agent attestation:

```console
cat intermediate/certs/node.cert.pem \
   intermediate/certs/intermediate.cert.pem > intermediate/certs/node-bundle.cert.pem
```

We will use `intermediate/certs/node-bundle.cert.pem` and `intermediate/private/node.key.pem`
in SPIRE Agent.
