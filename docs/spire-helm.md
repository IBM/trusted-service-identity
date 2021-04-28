# Deploying Tornjak with Helm charts
This tutorial demonstrates the steps required to deploy Tornjak elements in Kuberentes
cluster.

There are two helm charts available:
* tornjak - this helm chart deploys Tornjak server, SPIRE Server and all the components to support the management. Additionally, this chart contains a plugin for deploying [OIDC component](./spire-oidc-tutorial.md)
* spire - this helm chart deploys SPIRE agents, one per every worker node. Additionally, the chart also install some optional elements like [workload registrar](./spire-workload-registrar.md) and webhook (TBD).

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


## Important information
It is worth mentioning that once the trust domain is set, the SPIRE server persists the information locally (either on the host or via COS) and any consequent installation requires using the same trust domain. The easiest way to change the trust domain, is to remove all the SPIRE data under /run/spire/date directory, or delete the persistent volume claims (in COS), prior to installing the Tornjak server.
Deploy on non-OpenShift Kubernetes platform
To deploy Tornjak and all required services on the non-OpenShift Kubernetes platform we will use helm charts.
Step 1. Deploy a Tornjak with SPIRE Server
The first part of the tutorial deploys Tornjak bundled with SPIRE Server using helm charts.

## Deployment
We can deploy the helm charts on any Kubernetes platform. [Here are instructions](./spire-on-openshift.md) for installing on OpenShift.

For purpose of this tutorial we can deploy it on minikube (https://minikube.sigs.k8s.io/docs/start/)

```console
minikube start --kubernetes-version=v1.20.2
```

### Create a namespace
Once the cluster is up and the `KUBECONFIG` is defined, create the namespace to deploy Tornjak server. By default we would use “tornjak” and "minikube" as cluster name.

```
kubectl create ns tornjak
export CLUSTERNAME=minikube
```

### Create Keys
Next step is to co create private key and certificates based on a given CA. If you have don’t have your roocCA, use the sample one from here: https://github.com/lumjjb/tornjak/tree/main/sample-keys/ca_process/CA

Use “utils/createKeys.sh” script to setup keys. Pass cluster name and domain name associate with your ingress:

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

## Helm Deployment
Now we should be ready to deploy the helm charts. This Helm chart requires several configuration parameters:
* clustername - name of the cluster (required)
* trustdomain - must match between SPIRE server and agents (required)
* namespace - using “tornjak” by default

To get a complete list of values:
```
helm inspect values charts/tornjak/
```

Sample execution:
```console
helm install --set "namespace=tornjak" --set "clustername=$CLUSTERNAME" --set "trustdomain=openshift.space-x.com" tornjak charts/tornjak --debug
```

## Setup Ingress
Ingress represents the external access to the cluster. The ingress setup depends on the Cloud service provider, so please refer to individual cloud documentation.

Setting up ingress for [minikube](https://kubernetes.io/docs/tasks/access-application-cluster/ingress-minikube/)

There are currently 4 services that required Ingress access, here are their names and ports:
```
NAME           TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)           AGE
spire-server   NodePort   10.98.205.215   <none>        8081:30770/TCP    158m
tornjak-http   NodePort   10.100.246.18   <none>        10000:32758/TCP   158m
tornjak-mtls   NodePort   10.111.38.89    <none>        30000:30238/TCP   158m
tornjak-tls    NodePort   10.108.8.17     <none>        20000:30258/TCP   158m
```

“spire-server” service is used by the SPIRE agents and Workload Registrar to communicate with the SPIRE server and it needs to be accessible to them (used in step 2).
The “tornjak-*” services are used to access Tornjak server.

On minikube, retrieve the access points using service names:

```console
minikube service spire-server -n tornjak --url
http://192.168.99.112:30064
minikube service tornjak-http -n tornjak --url
http://192.168.99.112:32390
minikube service tornjak-tls -n tornjak --url
http://192.168.99.112:30670
```

Now you can test the connection to Tornjak by going to `http://192.168.99.112:32390` using your local browser, or secure (HTTPS) connection here: `https://192.168.99.112:30670`

In case of minikube, we will use the following for accessing the SPIRE server:

```console
export SPIRE_SERVER=192.168.99.112
export SPIRE_PORT=30064
```

If we use other platforms, setup the Ingress values accordingly:
```
export SPIRE_SERVER=<Ingress value to spire-server service>
export SPIRE_PORT=<Port value for spire-server service>
```

## Step 2. Deploy a SPIRE Agent and Workload Registrar
This part of the tutorial deploys SPIRE Agents, one per each worker node. It also deploys the optional component Workload Registrar that dynamically creates SPIRE entries.
More about the workload registrar [here](./spire-workload-registrar.md).

We suggest NOT to run more than one instance of SPIRE Agent deployment. One of them might crash, even if running in a different namespace.

First create a namespace where we want to deploy our SPIRE agents. For the purpose of this tutorial we will use “spire”.

Now we need to copy the spire-bundle that contains all the keys and certificates, from the SPIRE server to this new namespace. Assuming both are deployed in the same cluster, just in a different namespaces, the format is following:

```console
kubectl get configmap spire-bundle -n "$SPIRESERVER_NS" -o yaml | sed "s/namespace: $SPIRESERVER_NS/namespace: $AGENT_NS/" | oc apply -n "$AGENT_NS" -f -
```
Where in our example, `$SPIRESERVER_NS` is “tornjak” and `$AGENT_NS` is “spire”:

```console
kubectl get configmap spire-bundle -n "tornjak" -o yaml | sed "s/namespace: tornjak/namespace: spire/" | kubectl apply -n "spire" -f -
```

Next step, we need to define access to the SPIRE Server. This is typically the Ingress value defined during the SPIRE Server deployment above:

```console
export SPIRE_SERVER=192.168.99.112
export SPIRE_PORT=30064
```
For the purpose of this tutorial, where both server and agents are deployed in the same cluster, we can either use the Ingress values defined above, or we can use `ExternalName Service`, and point at the service created in a different namespace (e.g. tornjak):

```console
kubectl -n spire create -f- <<EOF
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

export SPIRE_SERVER=spire-server.tornjak.svc.cluster.local
export SPIRE_PORT=8081
```

Now we can deploy the helm chart, assuming SPIRE server can be accessed (either via Ingress or Service on port 8081).

Here we continue using the same cluster name “minikube” and trust domain “openshift.space-x.com”.

`--debug` flag shows additional information about the helm deployment:

```
helm install --set "spireAddress=$SPIRE_SERVER" --set "spirePort=$SPIRE_PORT"  --set "namespace=spire" --set "clustername=minikube" --set "trustdomain=openshift.space-x.com" spire charts/spire --debug
```

When successfully executed, the helm chart shows NOTES output.  Something like this:

```
NOTES:
The installation of the SPIRE Agent and Workload Registrar for
Universal Trusted Workload Identity Service has completed.

  Cluster name: tsi-kube01
  Trust Domain: openshift.space-x.com
  Namespace:    spire

  SPIRE info:
      Spire Server address:  spire-server.tornjak.svc.cluster.local:8081
      Spire Agent image: gcr.io/spiffe-io/spire-agent:0.12.1
      Spire Registrar image: gcr.io/spiffe-io/k8s-workload-registrar:0.12.1


To enable Workload Registrar, create an entry on Tornjak UI:
1. find out what node the registrar is running on:
    kubectl -n spire1 get pods -o wide
2. get the SPIFFE ID of the agent for this node (Tornjak -> Agents -> Agent List)
3. create Entry (Tornjak -> Entries -> Create Entry) using appropriate Agent
SPIFFE ID as Parent ID:

  SPIFFE ID:
    spiffe://openshift.space-x.com/tsi-kube01/workload-registrar
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
```
helm ls
NAME       NAMESPACE    REVISION    UPDATED                                 STATUS      CHART            APP VERSION
spire      default      1           2021-04-26 11:16:37.327068 -0400 EDT    deployed    spire-0.1.0      0.1
tornjak    default      1           2021-04-22 18:27:54.712062 -0400 EDT    deployed    tornjak-0.1.0    0.1
```

Let's review the deployment. First the Tornjak deployment:
```
kubectl -n tornjak get po
NAME             READY   STATUS    RESTARTS   AGE
spire-server-0   1/1     Running   0          20m
```
And now, the SPIRE agents deployment. Since this is running on minikube with only one node, there should be only one SPIRE agent active:
```
kubectl -n spire get po
NAME                               READY   STATUS    RESTARTS   AGE
spire-agent-4g8tg                  1/1     Running   0          20m
spire-registrar-85fcc94797-r8rc8   1/1     Running   0          20m
```

This looks good. The next step is [registering The Workload Registrar with the SPIRE Server](./spire-workload-registrar.md).