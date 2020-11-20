# Trusted Service Identity Demo with Keycloak
[Keycloak](https://www.keycloak.org/) is an open-sourced tool for Identity and Access Managment

This demo can be executed alone or in addition to secrets management [demo with Vault](/examples/vault/README.md)

## Table of Contents
- [Prerequisites](./README.md#prerequisites)
- [Configuration](./README.md#configuration)
- [Keycloak Installation](./README.md#keycloak-installation)
- [Keycloak Access Policies](./README.md#keycloak-access-policies)
- [Sample Application](./README.md#sample-application)

## Prerequisites
This demo requires complete [TSI installation](/README.md#install-trusted-service-identity-framework), including registration of all the
[nodes with Vault](/examples/vault/README.md#register-jwt-signing-service-jss-with-vault)

## Configuration
Keycloak demo does not require any additional configuration changes. The only related
configuration is the frequency of identities retrieval from Keycloak (`identities.refreshSec`)
by default set to 600 seconds. To change this value, use the following syntax
as specified in [instructions](/README.md#deploy-helm-charts):

```console
helm install charts/ti-key-release-2-X.X.X.tgz --debug --name tsi \
--set ti-key-release-1.identities.refreshSec=600 \
. . .
```

## Keycloak Installation
To run the Keycloak demo we need a running instance of the Keycloak
service. This can be installed in the same Kubernetes cluster as
the demo, or in a remote location, as long as the demo cluster has access to the instance. It is a good practice to keep the Keycloak
instance in a separate namespace, e.g. `tsi-keycloak`.

First, define the KEYCLOAK_PASSWORD value in [/examples/keycloak/keycloak.yaml](/examples/keycloak/keycloak.yaml)

```console
kubectl create ns tsi-keycloak
kubectl -n tsi-keycloak create -f examples/keycloak/keycloak.yaml
service/tsi-keycloak created
deployment.apps/tsi-keycloak created
```

#### Obtain remote access to Keycloak service
For `minikube` obtain the current endpoint as follow
<details><summary>Click to view minikube steps</summary>

```console
minikube service tsi-keycloak -n tsi-keycloak --url
🏃  Starting tunnel for service tsi-keycloak.
|--------------|--------------|-------------|------------------------|
|  NAMESPACE   |     NAME     | TARGET PORT |          URL           |
|--------------|--------------|-------------|------------------------|
| tsi-keycloak | tsi-keycloak |             | http://127.0.0.1:61286 |
|--------------|--------------|-------------|------------------------|
http://127.0.0.1:61286
```
So this is the URL to get access to the Keycloak console from the host (browser).

If the application container is running in the same Minikube cluster, we need the
Cluster IP provided by the service.
```console
keycloak$k get service -n tsi-keycloak
NAME           TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)          AGE
tsi-keycloak   NodePort   10.106.55.60   <none>        9090:32548/TCP   3h15m
```
In this example the value is `http://10.106.55.60:9090`, and that's what we will
add to the application configuration deployment.

</details>


To access Keyclaok remotely in `IKS`, setup ingress access.
<details><summary>Click to view IKS steps</summary>

Obtain the ingress name using `ibmcloud` cli:
```console
$ # first obtain the cluster name:
$ ibmcloud ks clusters
$ # then use the cluster name to get the Ingress info:
$ ibmcloud ks cluster-get --cluster <cluster_name> | grep Ingress
```
Build an ingress file from `example/keycloak/ingress-IKS.template.yaml`,
using the `Ingress Subdomain` information obtained above. You can use any arbitrary
prefix in addition to the Ingress value. For example:
`host: tsi-keycloak.my-tsi-cluster-8abee0d19746a818fd9d58aa25c34ecfe-0000.eu-de.containers.appdomain.cloud`

```yaml
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: keycloak-ingress
spec:
  rules:
    # provide the actual Ingress for `host` value:
    # use the following command to get the subdomain:
    #    ibmcloud ks cluster get --cluster <cluster-name> | grep Ingress
    # any prefix can be defined as a result (e.g.):
    # - host: tsi-keycloak-v001.tsi-fra02-5240a746a818fd9d58aa25c34ecfe-0000.eu-de.containers.appdomain.cloud
    # provide the actual Ingress for `host` value:
  - host: tsi-keycloak.my-tsi-cluster-8abee0d19746a818fd9d58aa25c34ecfe-0000.eu-de.containers.appdomain.cloud
    http:
      paths:
      - backend:
          serviceName: tsi-keycloak
          servicePort: 9090
        path: /
```

create ingress:
```console
$ kubectl -n tsi-keycloak create -f ingress-IKS.yaml
```
</details>

To access Keycloak on OpenShift (including IKS ROKS)
<details><summary>Click to view OpenShift steps</summary>

This assumes the OpenShift command line is already installed. Otherwise see
the [documentation](https://docs.openshift.com/container-platform/4.2/cli_reference/openshift_cli/getting-started-cli.html)
and you can get `oc` cli from https://mirror.openshift.com/pub/openshift-v4/clients/oc/4.3/

```console
oc -n tsi-keycloak expose svc/tsi-keycloak
export KEYCLOAK_ADDR="http://$(oc -n tsi-keycloak get route tsi-keycloak -o jsonpath='{.spec.host}')"
```

</details>

Keycloak Configuration steps:
* Using the Keycloak URL obtained above, connect to the server with a browser and
login using admin userid and password, as specified in the [/examples/keycloak/keycloak.yaml](/examples/keycloak/keycloak.yaml)
* In upper left corner, below Keycloak logo, click on `Master` and select `Add realm`
* Select `Import` and navigate to [/examples/keycloak/tsi-realm-export.json](/examples/keycloak/tsi-realm-export.json) file. Press Create.

This should instantiate a new `Tsi-realm` realm that we would use for the demo.

## Keycloak Access Policies
By loading the `tsi-realm-export.json` into Keycloak, we configured most of components
needed for the demo. Now we just need to modify the policies to match your
environment.

During the [installation of TSI](/README.md#install-trusted-service-identity-framework), we used `CLUSTER_NAME` and `REGION` attributes. They were either given to us by the
service provider (IBM Cloud IKS or ROKS), or we defined them ourselves manually
(e.g. in Minikube)

These values, along with `images`, `namespace`,`pod-id`, etc, represent the identity
of the workload. We can use them to define policies that would restrict access
to specific resources.

For example, let's take a look a the Client `tsi-client`:
* Select `Clients`  --> `tsi-client`
* Select `Authorization` tab
* Select `Policies` tab
* Take a look at the given policies.
  - `tsi-policy` grants access if the `region` contains `eu`
  - `strict-image-policy` grants access if the `image-names` contains `myubuntu`
  - `restrict-cluster-tsi-and-namespace-test` grants the access if the `cluster-name`
exists and is equal to `minikube` value, and the `namespace` is `test`
* go ahead, and update the policies to match your values for `region`, `image-names`
and `cluster-name`

## Sample Application
Let's start an application that requests the injection of Keycloak identities.
Use provided [examples/keycloak/myubuntu.id.yaml](/examples/keycloak/myubuntu.id.yaml)
configuration and update the annotation to match your Keycloak server URL.

```yaml
annotations:
  admission.trusted.identity/inject: "true"
  # token-url: complete URL for obtaining a realm token:
  tsi.identities: |
    - tsi.keycloak/token-url: "http://10.106.55.60:9090/auth/realms/tsi-realm/protocol/openid-connect/token"
      tsi.keycloak/audiences: "tsi-client"
      tsi.keycloak/local-path: "tsi-secrets/identities"
```
where:
* `token-url` the Keycloak URL that can be accessed by the application container, either the Ingress (for IKS, ROKS) or the service ClusterIP and Port for Minikube. The URL also contains the realm value. E.g. "http://10.106.55.60:9090/auth/realms/tsi-realm/protocol/openid-connect/token"
* `audiences` - one (or many, comma separated) name of the client requesting the identity
* `local-path`- location where the identities would be injected. Must start with "tsi-secrets"

Create the deployment in `test` namespace
```console
kubectl -n test -f examples/keycloak/myubuntu.id.yaml
kubectl -n test get pods -w
```

Once the pod is in "Running" state, exec to it:

```console
kubectl -n test exec -it <pod-id> -- bash
```

Access tokens would be injected in `/tsi-secrets/identities` directory.
For every audience member, TSI injects 2 files: access token obtained from Keycloak,
and its decoded value (.txt), where the filenames reflect the provided audience value.

Here is a sample output:
```console
root@myubuntuid-7f5897844b-v9whh:/# ls -l /tsi-secrets/identities/
total 8
-rw------- 1 root root 3242 Nov 19 14:35 access_token.tsi-client.0
-rw-r--r-- 1 root root 1648 Nov 19 14:35 access_token.tsi-client.0.txt
root@myubuntuid-7f5897844b-v9whh:/# cat /tsi-secrets/identities/access_token.tsi-client.0.txt
{
  "exp": 1605797112,
  "iat": 1605796512,
  "jti": "30fc4568-7111-4f31-8bfc-4b7af2f1a211",
  "iss": "http://10.106.55.60:9090/auth/realms/tsi-realm",
  "aud": "tsi-client",
  "sub": "16e4c362-e005-4c0b-8246-5963de268e76",
  "typ": "Bearer",
  "azp": "tsi-client",
  "session_state": "3075c4c1-94c6-4a3e-a255-75ca7d3729cc",
  "acr": "1",
  "realm_access": {
    "roles": [
      "offline_access",
      "uma_authorization"
    ]
  },
  "resource_access": {
    "tsi-client": {
      "roles": [
        "uma_protection"
      ]
    },
    "account": {
      "roles": [
        "manage-account",
        "manage-account-links",
        "view-profile"
      ]
    }
  },
  "authorization": {
    "permissions": [
      {
        "scopes": [
          "read",
          "write"
        ],
        "rsid": "f427020d-749c-4b93-8ca9-84ca6765711d",
        "rsname": "some.url/mrsabath/table"
      },
      {
        "scopes": [
          "read",
          "write"
        ],
        "rsid": "1af97ebf-0fa1-4715-85c5-62d3a146e6e2",
        "rsname": "my-cloudant.example.com/mycollection"
      }
    ]
  },
  "scope": "profile email",
  "images-names": "ubuntu@sha256:250cc6f3f3ffc5cdaa9d8f4946ac79821aafb4d3afc93928f0de9336eba21aa4",
  "images": "30beed0665d9cb4df616cca84ef2c06d2323e02869fcca8bbfbf0d8c5a3987cc",
  "clientHost": "172.18.0.9",
  "machineid": "a50bd65ebf564225b7e591d08c43fef9",
  "email_verified": false,
  "clientId": "tsi-client",
  "pod": "myubuntuid-7f5897844b-v9whh",
  "namespace": "test",
  "preferred_username": "service-account-tsi-client",
  "region": "eu-de",
  "clientAddress": "172.18.0.9",
  "cluster-name": "minikube"
}
```
