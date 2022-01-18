# Vault Setup
Some demos require access to the Vault instance.
If you have a Vault instance, make sure you have admin privileges to access it.
Otherwise, follow the simple steps below to create a Vault instance, as a pod and
service, deployed in `tsi-vault` namespace in your cluster.

## Vault Instance Deployment
We are using the following deployment file:
[../examples/vault/vault.yaml](../examples/vault/vault.yaml)

```console
kubectl create namespace tsi-vault
kubectl -n tsi-vault create -f examples/vault/vault.yaml
service/tsi-vault created
deployment.apps/tsi-vault created
```

#### Obtain remote access to Vault service
For `minikube` obtain the current endpoint as follow
<details><summary>Click to view minikube steps</summary>

```console
minikube service tsi-vault -n tsi-vault --url
http://192.168.99.105:30229
# assign it to VAULT_ADDR env. variable:
export VAULT_ADDR=http://192.168.99.105:30229
```
</details>


To access Vault remotely in `IKS`, setup ingress access.
<details><summary>Click to view IKS steps</summary>

Obtain the ingress name using `ibmcloud` cli:
```console
$ # first obtain the cluster name:
$ ibmcloud ks clusters
$ # then use the cluster name to get the Ingress info:
$ ibmcloud ks cluster get --cluster <cluster_name> | grep Ingress
Ingress Subdomain:              tsi-kube01-xxxxxxxxxxx-0000.eu-de.containers.appdomain.cloud
Ingress Secret:                 tsi-kube01-xxxxxxxxxxx-0000
Ingress Status:                 healthy
Ingress Message:                All Ingress components are healthy
```
Build an ingress file from `example/vault/ingress.IKS.template.yaml`,
using the `Ingress Subdomain` information obtained above. You can use any arbitrary
prefix in addition to the Ingress value. For example:

`host: tsi-vault.my-tsi-cluster-xxxxxxxxxxx-0000.eu-de.containers.appdomain.cloud`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: vault-ingress
  namespace: tsi-vault
spec:
  rules:
  - host: tsi-vault.my-tsi-cluster-xxxxxxxxxxx-0000.eu-de.containers.appdomain.cloud
    http:
      paths:
      - pathType: Prefix
        path: "/"
        backend:
          service:
            name: tsi-vault
            port:
              number: 8200
```

create ingress:
```console
$ kubectl -n tsi-vault create -f ingress-IKS.yaml
```

Create VAULT_ADDR env. variable:
```console
export VAULT_ADDR="http://<Ingress>"
```
</details>

To access Vault remotely OpenShift (including IKS ROKS)
<details><summary>Click to view OpenShift steps</summary>

This assumes the OpenShift command line is already installed. Otherwise see
the [documentation](https://docs.openshift.com/container-platform/4.2/cli_reference/openshift_cli/getting-started-cli.html)
and you can get `oc` cli from https://mirror.openshift.com/pub/openshift-v4/clients/oc/4.3/

```console
oc -n tsi-vault expose svc/tsi-vault
export VAULT_ADDR="http://$(oc -n tsi-vault get route tsi-vault -o jsonpath='{.spec.host}')"
export ROOT_TOKEN=$(kubectl -n tsi-vault logs $(kubectl -n tsi-vault get po | grep tsi-vault-| awk '{print $1}') | grep Root | cut -d' ' -f3); echo "export ROOT_TOKEN=$ROOT_TOKEN"
```

</details>

Test the remote connection to vault:
```console
$ curl  http://<Ingress Subdomain or ICP master IP>/
<a href="/ui/">Temporary Redirect</a>.
```
At this point, this is an expected result.

Once the Vault service is running and `VAULT_ADDR` is defined,
Vault requires a setup. See a demo specifics to continue.
<!-- Vault setup:

```console
examples/vault/demo.vault-setup.sh $VAULT_ADDR tsi-vault
``` -->
