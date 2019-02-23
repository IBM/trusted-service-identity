# Trusted Identity Examples - Application Developer
This document guides through adapting your application to be used with Trusted Service Identity

## Assumptions
We assume that at this point you have a working K8s cluster with Trusted Service Identity
environment deployed, including the sample Key Store and JWKS public key is also
registered with the Key Store. Otherwise, please see [example/README.md](./README.md)

## Deploy sample application
Deploy the sample application and exec into it:

```
kubectl create -f examples/myubuntu.yaml -n trusted-identity
alias k="kubectl -n trusted-identity"
k exec -it $(k get po | grep myubuntu | awk '{print $1}') /bin/bash
```
JWT Tokens by default are created every 30 seconds and they are available in `/jwt-tokens`
directory. One can inspect the content of the token by simply pasting it into
[Debugger](https://jwt.io/) in Encoded window.
Sample Payload:

```json
{
  "cluster-name": "mycluster",
  "cluster-region": "dal13",
  "exp": 1550871343,
  "iat": 1550871313,
  "images": "res-kompass-kompass-docker-local.artifactory.swg-devops.com/myubuntu:latest@sha256:5b224e11f0e8daf35deb9aebc86218f1c444d2b88f89c57420a61b1b3c24584c",
  "iss": "wsched@us.ibm.com",
  "machineid": "266c2075dace453da02500b328c9e325",
  "namespace": "trusted-identity",
  "pod": "myubuntu-698b749889-vvgts",
  "sub": "wsched@us.ibm.com"
}
```

## Validate that JWKS from this cluster is already registered with a Key Store
If the public JWKS is registered with the Key Store, all the requests that have
the same cluster-name, will be using the registered JWKS.
To test the access, simply execute the request to get back the claim values:

```console
root@myubuntu-698b749889-vvgts:/# curl --insecure https://198.11.242.156/ --header "Authorization: Bearer $(cat /jwt-tokens/token)"
JWT Claims: {u'cluster-name': u'mycluster', u'iss': u'wsched@us.ibm.com', u'cluster-region': u'dal13', u'namespace': u'trusted-identity', u'exp': 1550889622, u'machineid': u'266c2075dace453da02500b328c9e325', u'images': u'res-kompass-kompass-docker-local.artifactory.swg-devops.com/myubuntu:latest@sha256:5b224e11f0e8daf35deb9aebc86218f1c444d2b88f89c57420a61b1b3c24584c', u'iat': 1550889592, u'pod': u'myubuntu-698b749889-vvgts', u'sub': u'wsched@us.ibm.com'}
```

## Attempt to retrieve a secret from the Key Store using the JWT token
While still in the myubuntu container, attempt to obtain value of `cloudant-key-name`
from the KeyStore:

```
root@myubuntu-698b749889-vvgts:/# # access to keystore:
root@myubuntu-698b749889-vvgts:/# KEYSTORE_URL=https://198.11.242.156

root@myubuntu-698b749889-vvgts:/# curl --header "Authorization: Bearer $(cat /jwt-tokens/token)"  --insecure ${KEYSTORE_URL}/get/cloudant-key-name

<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN">
<title>404 Not Found</title>
<h1>Not Found</h1>
<p>Claims did not match any secret policy: {u'cluster-name': u'mycluster', u'iss': u'wsched@us.ibm.com', u'cluster-region': u'dal13', u'namespace': u'trusted-identity', u'exp': 1550890963, u'machineid': u'266c2075dace453da02500b328c9e325', u'images': u'res-kompass-kompass-docker-local.artifactory.swg-devops.com/myubuntu:latest@sha256:5b224e11f0e8daf35deb9aebc86218f1c444d2b88f89c57420a61b1b3c24584c', u'iat': 1550890933, u'pod': u'myubuntu-698b749889-vvgts', u'sub': u'wsched@us.ibm.com'}</p>
root@myubuntu-698b749889-vvgts:/#
```

The error above is expected, as we don't have any policy that allows anyone with
claims provided in JWT to obtain any secret.

## Create a new policy
Using the claims listed above, let's create a new policy that allows access to the
secrets:
* 'cloudant-key-name'='MY_CLOUDANT_KEY_NAME'
* 'cloudant-key-value'='MY_CLOUDANT_KEY_VALUE'
ONLY if the claims are as follow:
* 'cluster-name'='mycluster'  AND
* 'cluster-region'='dal13'

NOTE: This is just the Demo example. In our PRODUCTION example, access to create
policy WILL BE PROTECTED by secret SSH keys and/or password.

So now, let's pretend we are an admin that creates the new policies:
```console
# this key has access to US limited info only
NAME=MY_CLOUDANT_KEY_NAME
KEY=MY_CLOUDANT_KEY_VALUE
# assign to cluster: `mycluster` and region: `dal13`:
curl --insecure "${KEYSTORE_URL}/add?secretKey=cloudant-key-name&secretVal=${NAME}&cluster-name=mycluster&cluster-region=dal13"
curl --insecure "${KEYSTORE_URL}/add?secretKey=cloudant-key-value&secretVal=${KEY}&cluster-name=mycluster&cluster-region=dal13"
```

## Run the application
Since the policies were created, now let's re-run the request to get the API key name
and the value:

```console
root@myubuntu-698b749889-vvgts:/# export USERNAME=$(curl --header "Authorization: Bearer $(cat /jwt-tokens/token)"  --insecure ${KEYSTORE_URL}/get/cloudant-key-name)
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100    20  100    20    0     0     66      0 --:--:-- --:--:-- --:--:--    67
root@myubuntu-698b749889-vvgts:/# export API_KEY=$(curl --header "Authorization: Bearer $(cat /jwt-tokens/token)"  --insecure ${KEYSTORE_URL}/get/cloudant-key-value)
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100    21  100    21    0     0     72      0 --:--:-- --:--:-- --:--:--    73

root@myubuntu-698b749889-vvgts:/#
root@myubuntu-698b749889-vvgts:/# echo $USERNAME
MY_CLOUDANT_KEY_NAME
root@myubuntu-698b749889-vvgts:/# echo $API_KEY
MY_CLOUDANT_KEY_VALUE
```
All works great. Now your application can use the obtained secrets to retrieve data.

## Advanced example - JWT Cloudant client
More advanced client, used in the demo, creates the actual client for Cloudant
database that is retrieving Cloudant key name and value, and then attempting to
obtain values from Clouant. The client code is [examples/jwt-client/](./jwt-client/)
directory.

Let's deploy JWT Cloudant client. This simple program uses the JWT token
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
