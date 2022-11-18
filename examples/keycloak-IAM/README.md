# Tornjak Users Managment with Keycloak

This example explains how to use Keycloak as IAM tool for managing
Tornjak users.
When User Managment feature is enabled, Tornjak is configured to use external
IAM for managing access to SPIRE Server resources.
Basically, every call to Tornjak APIs, and in-directly to SPIRE Server APIs,
must include Bearer token with appropriate Tornjak roles.
For more information on Tornjak User Managment please refer to
[Tornjak documenation](https://github.com/spiffe/tornjak/blob/main/docs/keycloak-configuration.md)


## Standup Keycloak Instance
First we need to standup an instance of Keycloak.

Create a namespace dedicated to Keycloak
```console
create namespace keycloak
```

Create a Keycloak Deployment using a provided sample file [keycloak.yaml](./keycloak.yaml)
This would start a Development version of Keycloak instance,
along with Service "keycloak" running on port 8080.

By default, there are the following arguments defined for this instance:
```
env:
- name: PROXY_ADDRESS_FORWARDING
  value: "true"
- name: KEYCLOAK_ADMIN
  value: admin
- name: KEYCLOAK_ADMIN_PASSWORD
  value: adminpasswd
- name: KC_PROXY
  value: edge
- name: KEYCLOAK_FRONTEND_URL
  value: http://keycloak.tornjak.cloud/auth/
- name: KEYCLOAK_ADMIN_URL
  value: http://keycloak.tornjak.cloud/auth/realms/master/admin/
```

Please note these two URLs that represent the external access to this Keycloak
instance service. We will discuss the access next.

## Obtain remote access to Keycloak service
For `minikube` obtain the current endpoint as follow
<details><summary>[Click] to view minikube steps</summary>

```console
minikube service keycloak -n keycloak --url
http://192.168.99.105:30229

This is your access point for Keycloak service
```
</details>


To access Keycloak remotely on `IBM Cloud`, setup ingress access.
<details><summary>[Click] to view IKS steps</summary>

Obtain the ingress name using `ibmcloud` cli:
```console
$ # first obtain the cluster name:
$ ibmcloud ks clusters
$ # then use the cluster name to get the Ingress info:
$ ibmcloud ks cluster get --cluster <cluster_name> | grep Ingress
Ingress Subdomain:              tornjak-0000.region.containers.appdomain.cloud
Ingress Secret:                 tornjak-0000
Ingress Status:                 healthy
Ingress Message:                All Ingress components are healthy
```
Build an ingress file from `ingress.template.yaml`,
using the `Ingress Subdomain` information obtained above. You can use any arbitrary
prefix in addition to the Ingress value. For example:

`host: keycloak.tornjak-0000.region.containers.appdomain.cloud`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keycloak-ingress
spec:
  rules:
  - host: keycloak.tornjak-0000.region.containers.appdomain.cloud
    http:
      paths:
      - pathType: Prefix
        path: "/"
        backend:
          service:
            name: keycloak
            port:
              number: 8080
```

create ingress:
```console
$ kubectl -n keycloak -f ingress.keycloak.yaml
$ kubectl -n keycloak get ingress keycloak-ingress
```
This is your acess point for Keycloak service

</details>

To access Keycloak remotely OpenShift (including IKS ROKS)
<details><summary>[Click] to view OpenShift steps</summary>

This assumes the OpenShift command line is already installed. Otherwise see
the [documentation](https://docs.openshift.com/container-platform/4.2/cli_reference/openshift_cli/getting-started-cli.html)
and you can get `oc` cli from https://mirror.openshift.com/pub/openshift-v4/clients/oc/4.3/

```console
oc -n keycloak expose svc/keycloak
oc -n keycloak get route
```

This is your access point for Keycloak service
</details>

## Setup Keycloak to support IAM for Tornjak
[This blog](https://medium.com/universal-workload-identity/step-by-step-guide-to-setup-keycloak-configuration-for-tornjak-dbe5c3049034)
describes in details how to import configuration and setup Keycloak to support
user managment for Tornjak. The basic ideas are following:
* stand up the Keycloak instance and get access to it (we have done it)
* create "tornjak" realm
* obtain the tornjak realm resources file from [here](https://raw.githubusercontent.com/spiffe/tornjak/main/examples/Tornjak-keycloak-realm-import.json) and import the
settings
* create a sample user for accessing Tornjak portal
* [standup Tornjak with User Management enabled](./README.md#standup-tornjak-with-user-managment-enabled)
* test it all together


You can also refer to [Tornjak documentation](https://github.com/spiffe/tornjak/blob/main/docs/keycloak-configuration.md)

## Standup Tornjak with User Managment Enabled
Once your Keycloak Instance is operational and available to access remotely,
deploy Tornjak intstance as the standard deployment documented here, with
a minor changes that follow bellow:
* [simple Kubernetes, kind, minikube etc](../docs/spire-helm.md)
* [multi-cluster deployment](../docs/spire-multi-cluster.md)
* [openshift](../docs/spire-on-openshift.md)
* OIDC with [Vault](../docs/spire-oidc-vault.md) or [AWS S3](../docs/spire-oidc-aws-s3.md)

Changes required to support User Managment:
* update the [charts/tornjak/values.yaml](../charts/tornjak/values.yaml)
  * make sure both `enableUserMgment` and `separateFrontend` are set to *true*
  * `frontend.authServrURL` is set to the Keycloak access point for the service,
  as done above.
  * `frontend.apiServerURL` is set to Tornjak back-end service, typically `tornajak-http-tornjak` + the *Ingress* access point
  * `backend.jwksURL` is set to Keyclaok JWKS verification service, typically:
    *keycloak accesss point* + `/realms/tornjak/protocol/openid-connect/certs`
  * `backend.redirectUR` is a Keyclak URL for redirecting after successful authentication,
  typically: *Keycloak access point* + `/realms/tornjak/protocol/openid-connect/auth?client_id=Tornjak-React-auth`


  ```yaml
  tornjak:
     config:
       # enableUserMgment - when true, IAM configuration must be specified
       enableUserMgment: true
       # separateFrontend - when true, the frontend component is created under
       # a separate container
       separateFrontend: true
       # Front-end specific configurtion:
       frontend:
         # authServerURL - URL of the authentication server
         authServerURL: "http://keycloak.tornjak.appdomain.cloud"
         # apiServerURL - URL of the Tornjak back-end
         apiServerURL: "http://tornjak-http-tornjak.tornjak.appdomain.cloud"
       # Back-end specific configuration
       backend:
         # jwksURL - URL for JWKS verification
         jwksURL: "http://keycloak.tornjak.appdomain.cloud/realms/tornjak/protocol/openid-connect/certs"
         # redirectURL - URL for redirecting after successful authentication
         redirectURL: "http://keycloak.tornjak.appdomain.cloud/realms/tornjak/protocol/openid-connect/auth?client_id=Tornjak-React-auth"
  ```
* If deploying on Openshift, use `--itm` flag during the install
`utils/install-open-shift-tornjak.sh -c $CLUSTER_NAME -t example.org --oidc --iam`
