# Trusted Identity Examples - Demo
This demo sets up Key Server and sample JWT Cloudant client to demonstrate
how sample application can retrieve data securely from the Key Server using
Trusted Identity.

For a guidance how to create a custom application that is usinng Trusted Identity
see the following [Application Developer Guide](./README-AppDeveloper.md)

Demo steps:
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


## Deploy JWT Key Server
JWT Key Server is part of the included examples. Please note this only demonstrates
the capabilities and it should not be used for production.


### Build and create helm charts for JWT Key Server
The charts are already created, but if you like to modify the code and recreate them,
follow these steps:

```console
cd examples/
make all -C jwt-server/
# create the helm charts:
helm package charts/jwt-key-server
# move the helm package to examples/charts directory
mv jwt-key-server-X.X.X.tgz charts/
```

### Deploy the JWT Key Server via Helm
JWT Key Server can be deployed anywhere as long as it is accessible to
workloads in other clusters.

Deploy the JWT Key Server using helm and corresponding chart version:
```console
cd examples/
helm install charts/jwt-key-server-X.X.X.tgz --debug --name ti-jwt-server
```
If environment requires TLS communication for helm, like ICP, use `--tls` and corresponding chart version:
```console
helm install --tls charts/jwt-key-server-X.X.X.tgz --debug --name ti-jwt-server
```

The working example is using ICP cluster with master node on `198.11.242.156` IP.
This is our Ingress access point for this service.

### Deploy JWT Key Server directly
another option is to deploy the JWT Key Server directly

```console
# create the pod and service
cd examples
kubectl create -f examples/jwt-server-deploy.yaml
```

Note: _I am having some problems with conflicting Ingress when running in IKS, use the ICP, or just dedicate the cluster to just JWT Key Server_

Create ingress to access the Key Server remotely.

For IKS, obtain the ingress name using `ibmcloud` cli:
```console
# first obtain the cluster name:
ibmcloud ks clusters
# then use the cluster name to get the Ingress info:
ibmcloud ks cluster-get <cluster_name> | grep Ingress
```

Then create a file `ingress-IKS.yaml` using the `Ingress Subdomain` information
 obtained above:
```yaml
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
 name: ingress4jwtserver
spec:
  rules:
  - host: <Ingress Subdomain>
    http:
      paths:
      - path: /
        backend:
          serviceName: ti-jwt-server-jwt-key-server
          servicePort: 5000
```

create ingress:
```console
kubectl create ingress-IKS.yaml
```

Test the connection:
```console
$ curl  --insecure https://<Ingress Subdomain or ICP master IP>/
No Auth header exists
```

At this point, this is an expected result.


## Install JWKS keys for each vTPM deployment
For every deployment of vTPM, obtain JWKS and configure it on Key Server.

In order to obtain JWKS, connect to any container deployed in `trusted-identity`
namespace and get it using `curl http://vtpm-service:8012/getJWKS`.

As an example, let's connect to `myubuntu` created after installing TI above
and redirect the JWKS into a file `jwks.json`:

```console
alias k="kubectl -n trusted-identity"
k exec -it $(k get po | grep myubuntu | awk '{print $1}') /bin/bash
root@myubuntu-698b749889-pdp78:/# curl http://vtpm-service:8012/getJWKS > jwks.json
```

Now, while still in the `myubuntu` container, we can register this JWKS with our
JWT Key Server, using one of the attributes of the cluster created above.

For example `cluster-name=EUcluster` when our JWT Key Server is deployed on ICP
`https://198.11.242.156/`:

```console
root@myubuntu-698b749889-pdp78:/# curl --insecure "https://198.11.242.156/register?jwks=$(cat jwks.json | base64 -w 0)&cluster-name=EUcluster"
Registered jwks (sha256:d35262ea0693bc6c7a16ced26e111e4b1ef4efec95b3cbaa781f9ac4b5ad7b0e) with claims MultiDict([('cluster-name', u'EUcluster')])root@myubuntu-698b749889-pdp78:/#
```

From now on, all the requests that have cluster-name="EUcluster", will be using
the registered JWKS. To test the access, simply execute the request to get back
the claim values:

```console
root@myubuntu-698b749889-pdp78:/# curl --insecure https://198.11.242.156/ --header "Authorization: Bearer $(cat /jwt-tokens/token)"
JWT Claims: {u'cluster-name': u'EUcluster', u'iss': u'wsched@us.ibm.com', u'cluster-region': u'eu-de', u'exp': 1545313344, u'machineid': u'266c2075dace453da02500b328c9e325', u'images': u'res-kompass-kompass-docker-local.artifactory.swg-devops.com/myubuntu:latest@sha256:5b224e11f0e8daf35deb9aebc86218f1c444d2b88f89c57420a61b1b3c24584c', u'iat': 1545313314, u'pod': u'myubuntu-698b749889-pdp78', u'sub': u'wsched@us.ibm.com'}
root@myubuntu-698b749889-pdp78:/#

```

## Deploy JWT Cloudant client
Now we can deploy JWT Cloudant client. This simple program uses the JWT token
created by the sidecar to call JWT Key Server to obtain Cloudant API key for
retrieving data.

Update the deployment file _(this will be soon replaced by helm chart)_
[cloudant-client.demo.yaml](jwt-client/cloudant-client.demo.yaml) with the `KEYSTORE_URL` of the
JWT Key Server deployed earlier. In our example above:

```yaml
  - name: KEYSTORE_URL
    value: "https://198.11.242.156"
```
Then deploy it:

```console
kubectl create -f jwt-client/cloudant-client.demo.yaml
```

To access this deployment service remotely, update the ingress deployment file
[cloudant-client.demo.yaml](jwt-client/cloudant-client.demo.yaml)
with the actual Ingress value of `host` then deploy it.

For IKS, obtain the ingress name using `ibmcloud` cli:
```console
# first obtain the cluster name:
ibmcloud ks clusters
# then use the cluster name to get the Ingress info:
ibmcloud ks cluster-get <cluster_name> | grep Ingress
```

```console
kubectl create -f jwt-client/cloudant-client.ingress.yaml
```

If everything went well, you should be able to access you client using browser to
see the information obtained by the cloudant client. To format is:
`http://<Ingress>/jwt-client/`

http://ti-fra02.eu-de.containers.appdomain.cloud/jwt-client/

The sample output is:
```
Executing access to Cloudant tables...

====
2018-12-20 15:17:24
====

Container Identity

JWT Claims: {u'cluster-name': u'EUcluster', u'iss': u'wsched@us.ibm.com', u'cluster-region': u'eu-de', u'exp': 1545319065, u'machineid': u'266c2075dace453da02500b328c9e325', u'images': u'res-kompass-kompass-docker-local.artifactory.swg-devops.com/ti-jwt-client:v0.2@sha256:a570310501a881d6cedd56ac91bca33e655df479b29d8ff8d71bf1297e7c7f8d', u'iat': 1545319035, u'pod': u'cl-client-69447875d9-jqscg', u'sub': u'wsched@us.ibm.com'}

====

	NO MATCHING POLICIES FOR THIS IDENTITY!!

US data results

	NO DATABASE ACCESS!!


====

EU data results

	NO DATABASE ACCESS!!


====
2018-12-20 15:17:25
====
```

Time to create some policies...

## 7.0 Configure sample policies

```
# access to keystore:
KEYSTORE_URL=https://198.11.242.156

# Policy 1)
# this key has access to US limited info only
NAME=heriarystreformaddefachs
KEY=295d52e11c5c0b358dd3d18bb2192c5c23428f1d
# assign to `UScluster`
curl --insecure "${KEYSTORE_URL}/add?secretKey=cloudant-key-name&secretVal=${NAME}&cluster-name=UScluster"
curl --insecure "${KEYSTORE_URL}/add?secretKey=cloudant-key-value&secretVal=${KEY}&cluster-name=UScluster"

# Policy 2)
# this key has access to all the tables
NAME=iscepecomentsentstations
KEY=f3f16f7aaf23de897a7c4ed0bcc1e97539276e58
# assign to `UScluster` and `wdc01`
curl --insecure "${KEYSTORE_URL}/add?secretKey=cloudant-key-name&secretVal=${NAME}&cluster-name=UScluster&cluster-region=wdc01"
curl --insecure "${KEYSTORE_URL}/add?secretKey=cloudant-key-value&secretVal=${KEY}&cluster-name=UScluster&cluster-region=wdc01"

# Policy 3)
# EU + v0.1 image tag -->
# this key has access to EU details + US limited info
NAME=tedistripsaildesswasounn
KEY=224975fdbb1cdc1a232b5210c88d858a500c2a9b
# assign to `eu-de` and specific signed image
curl --insecure "${KEYSTORE_URL}/add?secretKey=cloudant-key-name&secretVal=${NAME}&cluster-region=eu-de&images=res-kompass-kompass-docker-local.artifactory.swg-devops.com/ti-jwt-client:v0.2@sha256:a570310501a881d6cedd56ac91bca33e655df479b29d8ff8d71bf1297e7c7f8d"
curl --insecure "${KEYSTORE_URL}/add?secretKey=cloudant-key-value&secretVal=${KEY}&cluster-region=eu-de&images=res-kompass-kompass-docker-local.artifactory.swg-devops.com/ti-jwt-client:v0.2@sha256:a570310501a881d6cedd56ac91bca33e655df479b29d8ff8d71bf1297e7c7f8d"
```

After setting above policies the output from cluster `EUcluster` and region `eu-de`
should look like this:

```console
Executing access to Cloudant tables...

====
2018-12-20 16:59:37
====

Container Identity

JWT Claims: {u'cluster-name': u'EUcluster', u'iss': u'wsched@us.ibm.com', u'cluster-region': u'eu-de', u'exp': 1545325203, u'machineid': u'266c2075dace453da02500b328c9e325', u'images': u'res-kompass-kompass-docker-local.artifactory.swg-devops.com/ti-jwt-client:v0.2@sha256:a570310501a881d6cedd56ac91bca33e655df479b29d8ff8d71bf1297e7c7f8d', u'iat': 1545325173, u'pod': u'cl-client-69447875d9-jqscg', u'sub': u'wsched@us.ibm.com'}
US data results

	Williams Bruce 	SSN:-- phone:--- rating:0
	Johnson Don 	SSN:-- phone:--- rating:10
	Sullivan Anne 	SSN:-- phone:--- rating:86
	Scarpetta John 	SSN:-- phone:--- rating:100
	Smith Alice 	SSN:-- phone:--- rating:20
	Brown Sally 	SSN:-- phone:--- rating:10

====

EU data results

	Schmidt Lena 	SSN:321-50-9677 phone:202-555-0185 rating:86
	Nowak Luis 	SSN:126-36-7299 phone:202-555-0167 rating:10
	Muller Mia 	SSN:161-54-6808 phone:202-555-0144 rating:100
	Bernard Ingrid 	SSN:451-91-5099 phone:202-555-0122 rating:20
	Ferrari Giotto 	SSN:527-30-7107 phone:202-555-0153 rating:0
	Rossi Lotte 	SSN:238-24-2096 phone:202-555-0121 rating:10

====
2018-12-20 16:59:39
====
```
