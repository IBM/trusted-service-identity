# Deploying Tornjak with Helm charts
This tutorial demonstrates the steps to deploy Tornjak and SPIRE elements
in a Kubernetes cluster.

There are two helm charts available:
* **tornjak** - this helm chart deploys the Tornjak server and the SPIRE Server. Additionally, this chart contains a plugin for deploying OIDC component that is used for [OIDC Tutorial](./spire-oidc-tutorial.md)
* **spire** - this helm chart deploys SPIRE agents, one per every worker node. Additionally, the chart installs some optional elements like [workload registrar](./spire-workload-registrar.md) and webhook (TBD).

## Prerequisites
The following installation was tested with:
* Kubernetes version 1.18 +
* Helm version 3

We used the following platforms for testing:
* Minikube
* Kind
* Red Hat OpenShift (see [instructions here](./spire-on-openshift.md))
* IBM Cloud - Kubernetes Service

Tutorial requirements:
* [git client](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
* [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
* [helm3 client](https://helm.sh/docs/intro/install/)

For our tutorial, we would use the following parameters:
* Platform: `minikube`
* Cluster name: `minikube`
* Trust domain: `openshift.space-x.com`
* Tornjak namespace: `tornjak`
* Agents namespace: `spire`

## Important information
It is worth mentioning that once the trust domain is set, the SPIRE server persists the information locally (either on the host or via Persistent Storage) and any consequent installation requires using the same trust domain. The easiest way to change the trust domain, is to remove all the SPIRE data under `/run/spire/date` directory, or delete the persistent storage volume, prior to installing the Tornjak server.

## Step 0. Get code
Before starting the tutorial, get the most recent code to your local system.
All the SPIRE related work is kept under `spire-master` branch that is separate
from the default `master` branch.

```console
git clone git@github.com:IBM/trusted-service-identity.git
cd trusted-service-identity
git checkout spire-master
```

## Step 1. Deploy Tornjak with a SPIRE Server
The first part of the tutorial deploys Tornjak bundled with SPIRE Server using helm charts.

We can deploy the helm charts on any Kubernetes platform. [Here are instructions](./spire-on-openshift.md) for installing on OpenShift.

For this tutorial, we can deploy it all on [minikube](https://minikube.sigs.k8s.io/docs/start/)

```console
minikube start --kubernetes-version=v1.20.2
```

### Create a namespace
Once the cluster is up and the `KUBECONFIG` is set, create the namespace to deploy Tornjak server. By default we use “tornjak” as namespace and "minikube" as the cluster name.

```console
export CLUSTERNAME=minikube
export SPIRESERVER_NS=tornjak
kubectl create ns $SPIRESERVER_NS
```

### Multi-cluster Support
If you want to setup a SPIRE Server
that supports multi-cluster deployment
where SPIRE agents are distributed in several, remote clusters,
all reporting to a single SPIRE Server,
please follow the additional steps outlined here,
otherwise skip to [Helm Deployment](#helm-deployment)

### Capture the portable KUBCONFIG from remote clusters
SPIRE server attests the remote agents by verifying the KUBECONFIG configuration.
Therefore, for every remote cluster,
other then the cluster hosting the Tornjak,
we need KUBECONFIG information.

Gather the portable KUBECONFIGs for every remote cluster
and output them into individual files
using  `kubectl config view --flatten`.
Make sure to use `--flatten` flag as it makes the output portable:
```
export KUBECONFIG=....
export CLUSTERNAME=....
mkdir /tmp/kubeconfigs
kubectl config view --flatten > /tmp/kubeconfigs/$CLUSTERNAME
```

For example, to support 2 remote clusters
`cluster1` and `cluster2`
we will have the following files:
```
/tmp/kubeconfigs/cluster1
/tmp/kubeconfigs/cluster2
```

Then using these individual files,
create one secret in `tornjak` project.
_Note_: don't use special characters, stick to alphanumerics.

```console
kubectl -n tornjak create secret generic kubeconfigs --from-file=/tmp/kubeconfigs
```
This has to be done before executing the Helm deployment.


## Helm Deployment
Now we should be ready to deploy the helm charts. This Helm chart requires several configuration parameters:
* clustername - name of the cluster (required)
* trustdomain - must match between SPIRE server and agents (required)
* namespace - using “tornjak” by default

To get a complete list of values:
```console
helm inspect values charts/tornjak/
```

### Multi-cluster Support
For multi-cluster scenario, update
[charts/tornjak/values.yaml](./charts/tornjak/values.yaml) file.
Include `name`, `namespace` and `serviceAccount`
for every remote cluster:
If not provided, it defaults to:
```
namespace: spire
serviceAccount: spire-agent
```
Here is a sample configuration:

```
multiCluster:
  remoteClusters:
  - name: cluster1
    namespace: spire
    serviceAccount: spire-agent
  - name: cluster2
  - name: cluster3
    namespace: spire
    serviceAccount: spire-agent
```
Then follow standard installation as shown below.


### Helm installation execution
Sample execution:
```console
helm install --set "namespace=tornjak" --set "clustername=$CLUSTERNAME" --set "trustdomain=openshift.space-x.com" tornjak charts/tornjak --debug
```

Let's review the Tornjak deployment:
```console
kubectl -n $SPIRESERVER_NS get pods
```
```
NAME             READY   STATUS    RESTARTS   AGE
spire-server-0   1/1     Running   0          2m
```
Looks good!

## Setup Ingress
If you are running these steps on local **minikube** you can skip this section and go directly to [Accessing Tornjak Server](#accessing-tornjak-server)

Ingress represents the external access to the cluster and it depends on the Cloud provider.

When deploying these helm charts on the **minikube** in the same cluster we can setup `ExternalName Service` to allow access to services in different namespace. These steps are described in Step 2. But if you like to setup external access, please see the following documentation for [minikube](https://kubernetes.io/docs/tasks/access-application-cluster/ingress-minikube/) and here is
for [kind](https://kind.sigs.k8s.io/docs/user/ingress/#using-ingress)

For other deployments, please refer to your specific cloud documentation.

Basically, we need the SPIRE agents to be able to communicate with the SPIRE Server. We also need to be able to access the **Tornjak** server with the browser.

Here is a complete list of services that require Ingress access, their names, and ports:

```console
kubectl get service -n $SPIRESERVER_NS
```

```
NAME           TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)           AGE
spire-server   NodePort   10.98.205.215   <none>        8081:30770/TCP    158m
tornjak-http   NodePort   10.100.246.18   <none>        10000:32758/TCP   158m
tornjak-mtls   NodePort   10.111.38.89    <none>        30000:30238/TCP   158m
tornjak-tls    NodePort   10.108.8.17     <none>        20000:30258/TCP   158m
```

For this tutorial we just need the first two `spire-server` (used in step 2) and `tornajk-http` to access the **Tornjak** server via simple HTTP.

On **minikube**, we can retrieve the access points using the service names:

```console
minikube service spire-server -n $SPIRESERVER_NS --url
```
```
http://192.168.99.112:30064
```
As as result, to access SPIRE server we would use the following:

```
export SPIRE_SERVER=192.168.99.112
export SPIRE_PORT=30064
```

On other platforms setup the Ingress values accordingly:
```
export SPIRE_SERVER=<Ingress value to spire-server service>
export SPIRE_PORT=<Port value for spire-server service>
```

## Accessing Tornjak Server
In this tutorial we just need the simple HTTP access to the Tornjak Server. For more advanced protocols, please refer to the section [Advanced Features](./spire-helm.md#advanced-features).

Get the HTTP Ingress access to Tornjak. On **minikube**, as seen above, we can retrieve the access points using the service names:

```console
minikube service tornjak-http -n $SPIRESERVER_NS --url
```
```
🏃  Starting tunnel for service tornjak-http.
|-----------|--------------|-------------|------------------------|
| NAMESPACE |     NAME     | TARGET PORT |          URL           |
|-----------|--------------|-------------|------------------------|
| tornjak   | tornjak-http |             | http://127.0.0.1:56404 |
|-----------|--------------|-------------|------------------------|
http://127.0.0.1:56404
❗  Because you are using a Docker driver on darwin, the terminal needs to be open to run it.

```

Now you can test the connection to the **Tornjak** server by going to `http://127.0.0.1:56404` using your local browser.

On **kind**, we can use port-forwarding to get HTTP access to Tornjak:

```
kubectl -n $SPIRESERVER_NS port-forward spire-server-0 10000:10000
```
```
Forwarding from 127.0.0.1:10000 -> 10000
Forwarding from [::1]:10000 -> 10000
```

Now you can test the connection to **Tornjak** server by going to `http://127.0.0.1:10000` in your local browser.

## Step 2. Deploy a SPIRE Agents
This part of the tutorial deploys SPIRE Agents as daemonset, one per worker node. It also deploys the optional component Workload Registrar that dynamically creates SPIRE entries. More about the workload registrar [here](./spire-workload-registrar.md).

Only ONE instance of SPIRE Agent deployment should be run at once as it runs a daemonset on all the node. Running more than one may result in conflicts.

First, create a namespace where we want to deploy our SPIRE agents. For the purpose of this tutorial, we will use “spire”.
```console
export AGENT_NS=spire
kubectl create namespace $AGENT_NS
```

Next, we need to get the `spire-bundle` that contains all the keys and certificates, from the SPIRE server and copy it to this new namespace. Assuming both are deployed in the same cluster, just in different namespaces, the format is following:

```console
kubectl get configmap spire-bundle -n "$SPIRESERVER_NS" -o yaml | sed "s/namespace: $SPIRESERVER_NS/namespace: $AGENT_NS/" | kubectl apply -n "$AGENT_NS" -f -
```
In our example this would be:
```console
kubectl get configmap spire-bundle -n tornjak -o yaml | sed "s/namespace: tornjak/namespace: spire/" | kubectl apply -n spire -f -
```

Next step, we need to set the public access to the SPIRE Server, so SPIRE agents can access it. This is typically the Ingress value defined during the SPIRE Server deployment above:

```
export SPIRE_SERVER=192.168.99.112
export SPIRE_PORT=30064
```
But for this tutorial, where both SPIRE server and SPIRE agents are deployed in the same cluster, we can either use the Ingress value defined above, or we can use `ExternalName Service` and point at the `spire-service` created in a different namespace (e.g. tornjak):

```console
kubectl -n $AGENT_NS create -f- <<EOF
kind: Service
apiVersion: v1
metadata:
  name: spire-server
spec:
  type: ExternalName
  externalName: spire-server.tornjak.svc.cluster.local
  ports:
  - port: 8081
EOF
```
Once created successfully, set up env. variable:
```console
export SPIRE_SERVER=spire-server.tornjak.svc.cluster.local
export SPIRE_PORT=8081
```
Assuming the SPIRE server can now be access from `spire` namespace, either via Ingress or Service on port 8081, we can deploy the helm charts.

We continue using the same cluster name “minikube”,
trust domain “openshift.space-x.com”
and region "us-east".

`--debug` flag shows additional information about the helm deployment:

```console
helm install --set "spireAddress=$SPIRE_SERVER" --set "spirePort=$SPIRE_PORT"  --set "namespace=$AGENT_NS" --set "clustername=$CLUSTERNAME" --set "region=us-east" --set "trustdomain=openshift.space-x.com" spire charts/spire --debug
```

When successfully executed, the helm chart shows NOTES output.  Something like this:

```
NOTES:
The installation of the SPIRE Agent and Workload Registrar for
Universal Trusted Workload Identity Service has completed.

  Cluster name: minikube
  Trust Domain: openshift.space-x.com
  Namespace:    spire

  SPIRE info:
      Spire Server address:  spire-server.tornjak.svc.cluster.local:8081
      Spire Agent image: gcr.io/spiffe-io/spire-agent:0.12.1
      Spire Registrar image: gcr.io/spiffe-io/k8s-workload-registrar:0.12.1


To enable Workload Registrar, create an entry on Tornjak UI:
1. find out what node the registrar is running on:
    kubectl -n spire get pods -o wide
2. get the SPIFFE ID of the agent for this node (Tornjak -> Agents -> Agent List)
3. create Entry (Tornjak -> Entries -> Create Entry) using appropriate Agent
SPIFFE ID as Parent ID:

  SPIFFE ID:
    spiffe://openshift.space-x.com/minikube/workload-registrar
  Parent ID:
    spiffe://openshift.space-x.com/spire/agent/k8s_psat/tsi-kube01/xxx
  Selectors:
    k8s:sa:spire-k8s-registrar,k8s:ns:spire,k8s:container-name:k8s-workload-registrar
  * check Admin Flag


  Chart Name: spire.
  Your release is named spire.

To learn more about the release, try:

  $ helm status spire
  $ helm get all spire
```

The steps relating to Workload Registrar will be useful in few minutes, but first let’s list all the helm deployments:
```console
helm ls
```
```
NAME       NAMESPACE    REVISION    UPDATED                                 STATUS      CHART            APP VERSION
spire      default      1           2021-04-26 11:16:37.327068 -0400 EDT    deployed    spire-0.1.0      0.1
tornjak    default      1           2021-04-22 18:27:54.712062 -0400 EDT    deployed    tornjak-0.1.0    0.1
```

Let's check the SPIRE agents deployment. Since this is running on minikube with only one node, there should be only one SPIRE agent active:
```console
kubectl -n spire get pods
```
```
NAME                               READY   STATUS    RESTARTS   AGE
spire-agent-4g8tg                  1/1     Running   0          20m
spire-registrar-85fcc94797-r8rc8   1/1     Running   0          20m
```

This looks good. The next step is [registering The Workload Registrar with the SPIRE Server](./spire-workload-registrar.md#register-workload-registrar-with-the-spire-server).

## Uninstall
To uninstall helm charts:
```console
helm uninstall spire
helm uninstall tornjak
```
To delete the minikube VM:
```console
minikube status
minikube delete
```

## Advanced Features
For a production usage, we want to better protect the access to various components.

### Keys for Tornjak TLS/mTLS
Tornjak access is available via HTTP, TLS and mTLS protocols. In a production
environment you should use TLS/mTLS that are based on certificates created from
the organization rootCA. If you just like to  test these protocols, and don't have
your own rootCA, you can use the sample from here: https://github.com/lumjjb/tornjak/tree/main/sample-keys/ca_process/CA
or create your own:

```
ROOTCA="sample-keys/CA/rootCA"
# Create CA certs:
openssl genrsa -out $ROOTCA.key 4096
openssl req -x509 -subj \"/C=US/ST=CA/O=Acme, Inc./CN=example.com\" -new -nodes -key $ROOTCA.key -sha256 -days 1024 -out $ROOTCA.crt
```
Put the `rootCA.key` and `rootCA.crt` files in `sample-keys/CA` directory.
Then use `utils/createKeys.sh` script to create private key and certificate.
Pass the cluster name and the domain name associated with your ingress:

The syntax is:
```console
utils/createKeys.sh <keys-directory> <cluster-name> <ingress-domain-name>
```
For our example, this is:
```console
utils/createKeys.sh sample-keys/ $CLUSTERNAME $INGRESS-DOMAIN-NAME
```

Create a secret that is using the generated key and certificates:

```
kubectl -n tornjak create secret generic tornjak-certs \
--from-file=key.pem="sample-keys/$CLUSTERNAME.key" \
--from-file=cert.pem="sample-keys/$CLUSTERNAME.crt" \
--from-file=tls.pem="sample-keys/$CLUSTERNAME.crt" \
--from-file=mtls.pem="sample-keys/$CLUSTERNAME.crt"
```

Then just simply restart the spire server by killing the **spire-server-0** pod

```
kubectl -n tornjak get pods
kubectl -n tornjak delete po spire-server-0
```

New pod should be created using the newly created secret with key and certs.

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

Now you can test the connection to Tornjak server by going to `http://127.0.0.1:56404` using your local browser, or secure (HTTPS) connection here: `http://127.0.0.1:30670`

Once TLS/mTLS access points are validated, in production we should disable the
HTTP service and HTTP Ingress for Tornjak.

For non-minikube environments open Ingress to either `tornjak-tls` or `tornjak-mtls` service and remove Ingress for `tornjak-http` service.
