# Trusted Service Identity Application Developer - using Key Server
This document guides through adapting your application to be used with Trusted
Service Identity with a Key Server.

Before starting to integrate your application with TIS, please make sure to run
the [Demo with Key Server](./jwt-server/README.md) first.

Demo components:
* [jwt-server](./jwt-server) - simple key server that stores access keys to
Cloudant
* [jwt-client](./jwt-client) - sample code that calls `jwt-server` with JWT token
to obtain keys to Cloudant.

If you like to see the Guide for Vault example, see it [here](./README-AppDeveloperVault.md).

## Assumptions
We assume that at this point you have a working K8s cluster with Trusted Service Identity
environment deployed, including the sample Key Store and public JWKS is
registered with the Key Store. Otherwise, please see [examples/README.md](./README.md)

## Deploy sample application
Deploy the sample application and exec into it:

```
kubectl create -f examples/myubuntu.yaml -n trusted-identity
alias k="kubectl -n trusted-identity"
k exec -it $(k get po | grep myubuntu | awk '{print $1}') /bin/bash
```
By default JWT Tokens are created every 30 seconds and they are available in `/jwt-tokens`
directory. One can inspect the content of the token by simply pasting it into
[Debugger](https://jwt.io/) in Encoded window.
Sample Payload:

```json
{
  "cluster-name": "ti_demo",
  "cluster-region": "dal09",
  "exp": 1557170306,
  "iat": 1557170276,
  "images": "f36b6d491e0a62cb704aea74d65fabf1f7130832e9f32d0771de1d7c727a79cc",
  "images-names": "res-kompass-kompass-docker-local.artifactory.swg-devops.com/myubuntu:latest@sha256:5b224e11f0e8daf35deb9aebc86218f1c444d2b88f89c57420a61b1b3c24584c",
  "iss": "wsched@us.ibm.com",
  "machineid": "fa967df1a948495596ad6ba5f665f340",
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
export KEYSTORE_URL=https://198.11.242.156
root@myubuntu-698b749889-vvgts:/# curl --insecure ${KEYSTORE_URL} --header "Authorization: Bearer $(cat /jwt-tokens/token)"

JWT Claims: {u'cluster-name': u'mycluster', u'iss': u'wsched@us.ibm.com', u'cluster-region': u'dal13', u'namespace': u'trusted-identity', u'exp': 1550889622, u'machineid': u'266c2075dace453da02500b328c9e325', u'images': u'res-kompass-kompass-docker-local.artifactory.swg-devops.com/myubuntu:latest@sha256:5b224e11f0e8daf35deb9aebc86218f1c444d2b88f89c57420a61b1b3c24584c', u'iat': 1550889592, u'pod': u'myubuntu-698b749889-vvgts', u'sub': u'wsched@us.ibm.com'}
```

## Attempt to retrieve a secret from the Key Store using the JWT token
While still in the `myubuntu` container, attempt to obtain value of `cloudant-key-name`
from the Key Store:

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

The error above is expected as we don't have any policy that allows anyone with
claims provided in JWT to obtain any secret.

## Create a new policy
Using the claims listed above, let's create a new policy that allows access to the
secrets:
* 'cloudant-key-name'='MY_CLOUDANT_KEY_NAME'
* 'cloudant-key-value'='MY_CLOUDANT_KEY_VALUE'

ONLY if the claims are as follow:
* 'cluster-name'='mycluster'  AND
* 'cluster-region'='dal13'

NOTE: This is just a demo example. In our PRODUCTION example, access to create
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
Since the policies are created, let's now re-run the request to get the API key name
and its value:

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
