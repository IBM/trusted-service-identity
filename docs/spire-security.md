# Enhanced SPIRE Security
Tornjak supports HTTP and HTTPS protocols, using TLS and mTLS.
In our demos we show the simples version, with HTTP.
Our standard deployment uses default Root CA available
[here](https://github.com/spiffe/tornjak/tree/main/sample-keys/ca_process/CA).

For obvious reasons,
this is just a sample certificate used for demonstration purpose only.
In your production deployment,
to better protect the access to various components,
you **should always use your own Root SSL certificate** that is issued by your own
Certificate Authority (CA) for signing all the TLS and mTLS certificates used
in the Tornjak deployment. Once the HTTPS access is well tested, you should
disable the HTTP access.

## Creating custom certificates for TLS/mTLS connections
The steps below show the process of creating your own private key
and the *self-signed* certificates.

If you don't have one,
create a private key and self-signed root CA.
Here is an example for Acme Inc. Organization:

```console
ROOTCA="sample-keys/CA/rootCA"
mkdir -p $ROOTCA
# Create CA certs:
openssl genrsa -out $ROOTCA.key 4096
openssl req -x509 -subj "/C=US/ST=CA/O=Acme, Inc./CN=example.com" -new -nodes -key $ROOTCA.key -sha256 -days 1024 -out $ROOTCA.crt
```

Make sure the `rootCA.key` and `rootCA.crt` files are in `sample-keys/CA` directory
before proceeding further.
This is the Root CA for your organization. Protect it well!

Then use `utils/createKeys.sh` script to create private key and certificate
to be used to secure the connections (TLS/mTLS) to the Tornjak Server.

Pass the *cluster name* and the *domain name* associated with your Cluster.
For multi-cluster scenarios, create a key and cert pair for each cluster.

The syntax is:
```console
utils/createKeys.sh <keys-directory> <cluster-name> <ingress-domain-name>
```

When using IBM Cloud, you can get these required values as follow:
```console
utils/get-cluster-info.sh
export CLUSTER_NAME=
export REGION=

INGRESS_DOMAIN_NAME=$(ibmcloud oc cluster get --cluster "$CLUSTER_NAME" --output json | jq -r '.ingressHostname')
```

In our example, this would be:
```console
utils/createKeys.sh sample-keys $CLUSTER_NAME $INGRESS_DOMAIN_NAME
```

Create a Kubernetes secret that is using the generated key and certificates.
*key.pem* and *tls.pem* correspond to the TLS connection.
*mtls.pem* is used for mTLS connection.
See the details
[here](https://github.com/spiffe/tornjak/blob/main/sample-keys/ca_process/README.md)

```console
kubectl -n tornjak create secret generic tornjak-certs \
--from-file=key.pem="sample-keys/$CLUSTER_NAME.key"  \
--from-file=tls.pem="sample-keys/$CLUSTER_NAME.crt" \
--from-file=mtls.pem="sample-keys/CA/rootCA.crt"
```

Then just simply restart the spire server by killing the **spire-server-0** pod

```console
kubectl -n tornjak get pods
kubectl -n tornjak delete po spire-server-0
```

New `spire-server-0` pod should be re-created using the values provided by
the newly created secret.

### Ingress for TLS/mTLS
As we setup HTTP ingress to Tornjak server earlier, to take advantage of the
secure connection we have to also enable TLS/mTLS ingress.

On **minikube**, we can retrieve the access points using service names:
```console
minikube service tornjak-http -n tornjak --url
http://127.0.0.1:56404
minikube service tornjak-tls -n tornjak --url
http://127.0.0.1:30670
minikube service tornjak-mtls -n tornjak --url
http://127.0.0.1:31740
```

Now you can test the above connections to Tornjak server by going to
`http://127.0.0.1:56404` using your local browser,
or a secure (HTTPS) connection: `https://127.0.0.1:30670`

You can also use curl for testing:
```console
# for tls:
curl -k --cacert sample-keys/CA/rootCA.crt https://127.0.0.1:30670
```

To test the mTLS connection we need to create a client certificate,
following the steps above. For example:

```console
utils/createKeys.sh sample-keys client localhost
```

Then test the mTLS connection:
```console
# for mtls:
curl -k --cacert sample-keys/CA/rootCA.crt --key sample-keys/client.key \
--cert sample-keys/client.crt https://127.0.0.1:31740
```

## Configure Tornjak Manager for HTTPS access
Start the Tornjak Manager

```console
docker run -p 50000:50000 -it tsidentity/tornjak-manager:latest
```

Then connect with a browser `http://localhost:50000/server/manage`.
Select *Manage Servers* and create connections.

### TLS Connection
Provide the unique name of your connection and URL Address:
  * `Server Name` - e.g. "space-x05 TLS"
  * `Address` - TLS endpoint for this Tornjak Server. e.g. "https://tornjak-tls-tornjak.space-x05-0000.us-east.containers.appdomain.cloud"

Check `TLS Enabled` button and provide the location of the CA cert file
e.g. `sample-keys/CA/rootCA.crt`

Then select *Register Server*

Now you can access all the Tornjak panels using the created Server Connection "space-x05 TLS"

### mTLS Connection
Provide the unique name of your connection and URL Address:
  * `Server Name` - e.g. "space-x05 MTLS"
  * `Address` - TLS endpoint for this Tornjak Server. e.g. "https://tornjak-mtls-tornjak.space-x05-0000.us-east.containers.appdomain.cloud"

Check `TLS Enabled` button and provide the location of the CA cert file
e.g. `sample-keys/CA/rootCA.crt`

Check `mTLS Enabled` button and provide the location of the client files
* `Cert File` e.g. `sample-keys/client.crt`
* `Key File` e.g. `sample-keys/client.key`
Then select *Register Server*

Now you can access all the Tornjak panels using the created Server Connection "space-x05 TLS"


## Disable HTTP access
Once TLS/mTLS access points are validated, in production we should disable the
HTTP service and HTTP Ingress for Tornjak.

For non-minikube environments remove *tornjak-http* service and Ingress for `tornjak-http` service.

```console
kubectl -n tornjak delete service tornjak-http

# in IBM Cloud, when using Ingress:
kubectl -n tornjak edit ingres spireingress
# and remove the http rule from your host

# then remove the route (for OpenShift)
kubectl -n tornjak delete route tornjak-http
```
