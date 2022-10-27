# Keycloak Deployment to Support IAM for Tornjak

Tornjak is a very popular open-source Identity Access Management solution, that
allows  management of users, their roles, and privileges for accessing a specific
system and applications. It has plenty of customizable features.
And it supports standard protocols such as OIDC (Open ID Connect).

## Keycloak Instance Deployment
Keycloak instance can be deployed in any location as long as it will be available
for Tornjak and the users to access.

1. Create a namespace e.g. `tornjak`
```console
kubectl create ns tornjak
```
1. Update the attributes in the Keycloak deployment file  
[examples/keycloak/keycloak.yaml](../examples/keycloak/keycloak.yaml)
  * `KEYCLOAK_ADMIN` - userid for the Keycloak admin
  * `KEYCLOAK_ADMIN_PASSWORD` - password for the Keycloak
  * `KEYCLOAK_FRONTEND_URL` - URL for the Keycloak Auhentication // TODO
  * `KEYCLOAK_ADMIN_URL` - URL for the Keycloak Admin realm // TODO

1. Create a Keycloak deployment
```console
kubectl create -f examples/keycloak/
```
This would start Keycloak instance as
Kubernetes [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
and a [Service](https://kubernetes.io/docs/concepts/services-networking/service/)

1. Get remote access to Keycloak service
For `minikube` obtain the current endpoint as follow
<details><summary>[Click] to view minikube steps</summary>

```console
minikube service tsi-keycloak -n keycloak --url
http://192.168.99.105:30229
# keycloak is running on the above address now
```
</details>


To access Keycloak remotely in `IKS`, setup ingress access.
<details><summary>[Click] to view IKS steps</summary>

Obtain the ingress name using `ibmcloud` cli:
```console
$ # first obtain the cluster name:
$ ibmcloud ks clusters
$ # then use the cluster name to get the Ingress info:
$ ibmcloud ks cluster get --cluster <cluster_name> | grep Ingress
Ingress Subdomain:              my-cluster-xxxxxxxxxxx-0000.eu-de.containers.appdomain.cloud
Ingress Secret:                 my-cluster-xxxxxxxxxxx-0000
Ingress Status:                 healthy
Ingress Message:                All Ingress components are healthy
```
Build an ingress file from `example/keycloak/ingress.template.yaml`,
using the `Ingress Subdomain` information obtained above. You can use any arbitrary
prefix in addition to the Ingress value. For example:

`host: keycloak.my-cluster-xxxxxxxxxxx-0000.eu-de.containers.appdomain.cloud`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keycloak-ingress
spec:
  rules:
  - host: keycloak.my-cluster-xxxxxxxxxxx-0000.eu-de.containers.appdomain.cloud
    http:
      paths:
      - pathType: Prefix
        path: "/"
        backend:
          service:
            name: tsi-keycloak
            port:
              # number: 9090
              number: 8080
```

create ingress:
```console
$ kubectl -n keycloak create -f examples/keycloak/ingress.template.yaml
```

Keycloak should be available under the address specified in `host`
</details>

To access Keycloak remotely OpenShift (including IKS ROKS)
<details><summary>[Click] to view OpenShift steps</summary>

This assumes the OpenShift command line is already installed. Otherwise see
the [documentation](https://docs.openshift.com/container-platform/4.2/cli_reference/openshift_cli/getting-started-cli.html)
and you can get `oc` cli from https://mirror.openshift.com/pub/openshift-v4/clients/oc/4.3/

```console
oc -n keycloak expose svc/tsi-keycloak
# get the Keycloak URL:
oc -n keycloak get route tsi-keycloak -o jsonpath='{.spec.host}'
```

Keycloak should be available under the above address.
</details>

Test the remote connection to vault:
```console
curl http://<Ingress>/ | grep "Welcome to Keycloak"
```

## Configure the Keycloak

// TODO
. . .

Test the connection to newly configured Keycloak:

```console
curl http://<Ingress>/realms/tornjak
```

## Configure the Tornjak
// TODO
. . .
