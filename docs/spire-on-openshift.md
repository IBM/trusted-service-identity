# Deploying Tornjak on OpenShift
This tutorial demonstrates the steps to deploy Tornjak elements on OpenShift platform. To see instructions for installing on non-OpenShift platform, please see the following documentation on [deploying Tornjak with helm charts](./spire-helm.md).

## Prerequisites
The following installation was tested with:
* Red Hat OpenShift 4.5 +
* Kubernetes version 1.18 +

Tutorial requirements:
* [git client](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
* [helm3 client](https://helm.sh/docs/intro/install/)
* [ibmcloud client](https://cloud.ibm.com/docs/cli?topic=cli-getting-started)
* [ibmcloud ks plugin](https://cloud.ibm.com/docs/containers?topic=containers-cs_cli_install)
* [openShift client (oc)](https://cloud.ibm.com/docs/openshift?topic=openshift-openshift-cli)
* [jq parser](https://stedolan.github.io/jq/)

For our tutorial, we would use following parameters:
* Platform: `openShift` (ROKS on IBMCloud)
* Cluster name: `space-x01`
* Trust domain: `openshift.space-x.com`
* Tornjak namespace: `tornjak`
* Agents namespace: `spire`

## Important information
**SPIRE Trust Domain** corresponds to the trust root of a SPIFFE identity provider.
A trust domain could represent an individual, organization, environment or department
running their own independent SPIFFE infrastructure.
All workloads identified in the same trust domain are issued identity documents
that can be verified against the root keys of the trust domain.

Each SPIRE server is associated with a single trust domain
that must be unique within that organization.
The trust domain takes the same form as a DNS name (for example, prod.acme.com), however it does not need to correspond to any DNS infrastructure.

*It is worth mentioning* that once the trust domain is set,
the SPIRE server persists the information locally
(either on the host or via Persistent Storage)
and any consequent installation requires using the same trust domain.
The easiest way to change the trust domain,
is to remove all the SPIRE data under `/run/spire/date` directory,
or delete the persistent storage volume,
prior to installing the Tornjak server.

## Deploy on OpenShift
For this tutorial, we will use OpenShift cluster running in IBM Cloud. To get a test cluster, Red Hat OpenShift on Kubernetes (ROKS) in IBM Cloud, follow the steps outlined here: https://www.ibm.com/cloud/openshift

Deployment of Tornjak Server on OpenShift in IBM Cloud is rather simple. Assuming all the OpenShift prereqs are satisfied, the installation can be done using provided scripts.
First create the OpenShift environment,
then configure the access to the this cluster using **admin** privileges.
Elevated permissions are required to setup the additional,
cluster level configurations.

When installing on
[ROKS](https://cloud.redhat.com/products/openshift-ibm-cloud)
(Red Hat® OpenShift®) on IBM Cloud™:
```console
ibmcloud ks clusters
export KUBECONFIG=$(mktemp).<clustername>.yaml
ibmcloud ks cluster config --admin -c <clustername>
echo "export KUBECONFIG=$KUBECONFIG"
```

Setup k8s configuration:
```console
export KUBECONFIG=<open-shift configuration>.yaml
```

Then test the connection:

```console
oc get config
oc get nodes
```

## Step 0. Get the installation code
Before starting the tutorial, get the most recent code to your local system.
All the SPIRE related work
has been integrated into `main` branch.
For the pre-SPIRE code, visit `main-no-spire` branch.

```console
git clone git@github.com:IBM/trusted-service-identity.git
cd trusted-service-identity
```

## Step 1. Installing Tornjak Server with SPIRE on OpenShift
To install Tornjak Server on OpenShift
we need some information about the cluster.

### Gather Cluster Info
When installing on
[ROKS](https://cloud.redhat.com/products/openshift-ibm-cloud)
(Red Hat® OpenShift®) on IBM Cloud™,
you can get cluster information by executing the following script:

```console
utils/get-cluster-info.sh
```
then export the output:
```
export CLUSTER_NAME=
export REGION=
```

### Create a Project (Kubernetes namespace)
Typically Tornjak server is installed in `tornjak` namespace.
If you like to change the default namespace,
make sure to use the actual name during the next steps of the deployment.

```console
export PROJECT=tornjak
oc new-project "$PROJECT" --description="My TSI Spire SERVER project on OpenShift" 2> /dev/null
```

### Multi-cloud Support
Single Tornjak/SPIRE server can support multiple remote clusters
as outlined in the [multi-cluster](./spire-multi-cluster.md) document.
Additionally, various Cloud providers are supported for the node attestion.
Follow the steps for [attesting the remote clusters](./spire-multi-cluster.md#attesting-the-remote-clusters) to enable multi-cluster support in Tornjak server deployment.

Then follow the standard installation as shown below.

### Advanced, more secure deployment
This demo deployment uses pre-created keys included with the helm chats.
To create your own keys, please follow [keys documentation](./spire-helm.md#keys-for-tornjak-tlsmtls)

### Run Tornjak installation script

Execute the installation script to get the most up to date syntax:

```
utils/install-open-shift-tornjak.sh

-c CLUSTER_NAME must be provided
Install SPIRE server for TSI

Syntax: utils/install-open-shift-tornjak.sh -c <CLUSTER_NAME> -t <TRUST_DOMAIN> -p <PROJECT_NAME> --oidc

Where:
  -c <CLUSTER_NAME> - name of the OpenShift cluster (required)
  -t <TRUST_DOMAIN> - the trust root of SPIFFE identity provider, default: spiretest.com (optional)
  -p <PROJECT_NAME> - OpenShift project [namespace] to install the Server, default: spire-server (optional)
  --oidc - execute OIDC installation (optional)
  --clean - performs removal of projects (allows additional parameters e.g. -p | --project)
```

Include the `CLUSTER_NAME` and the `TRUST_DOMAIN` as parameters. If you like to install in project (namespace) other than “tornjak”, pass the name with “-p” flag.

To use “--oidc” flag, please refer to our separate [OIDC document](./spire-oidc-tutorial.md).

This script detects a previous installation of Tornjak and prompts the user if the uninstallation is required.


```
utils/install-open-shift-tornjak.sh -c $CLUSTER_NAME -t trust-domain
```

Sample execution:
```console
utils/install-open-shift-tornjak.sh -c space-x01 -t openshift.space-x.com
```
This script takes care of the namespaces/project creation, sets up appropriate permissions, sets up the public access via Ingress, defines HTTP, TLS, and mTLS access points, and displays all the relevant information at the end.

Sample output:
```
The installation of the Tornjak with SPIRE Server for
Universal Trusted Workload Identity Service has completed.

      Cluster name: space-x01
      Trust Domain: openshift.space-x.com
      Tornjak Image: ghcr.io/spiffe/tornjak-spire-server:1.0.1
      SPIRE Server Socket: /run/spire/sockets/registration.sock

      Chart Name: tornjak
      Your release is named tornjak

To learn more about the release, try:

  $ helm status tornjak
  $ helm get all tornjak
NAME       NAMESPACE    REVISION    UPDATED                                 STATUS      CHART            APP VERSION
tornjak    tornjak      1           2021-04-21 14:47:08.228366 -0400 EDT    deployed    tornjak-0.1.0    0.1
route.route.openshift.io/spire-server created
NAME           HOST/PORT                                                                                                   PATH   SERVICES       PORT   TERMINATION   WILDCARD
spire-server   spire-server-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff-0000.us-south.containers.appdomain.cloud          spire-server   grpc   passthrough   None
spire-server-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff-0000.us-south.containers.appdomain.cloud
OK
All good
ingress.networking.k8s.io/spireingress created
route.route.openshift.io/tornjak-tls created
route.route.openshift.io/tornjak-mtls created
route.route.openshift.io/tornjak-http exposed
route.route.openshift.io/oidc created

export SPIRE_SERVER=spire-server-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff-0000.us-south.containers.appdomain.cloud

Tornjak (http): http://tornjak-http-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff-0000.us-south.containers.appdomain.cloud/
Tornjak (TLS): https://tornjak-tls-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff-0000.us-south.containers.appdomain.cloud/
Tornjak (mTLS): https://tornjak-mtls-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff-0000.us-south.containers.appdomain.cloud/
Trust Domain: openshift.space-x.com
```

Installation of the Tornjak and SPIRE server has completed. We will use the script output for the next steps.

## Step 2. Installing SPIRE Agents on OpenShift
These steps include the remote cluster installation

### Create a Project (Kubernetes namespace)
Typically SPIRE agents are installed in `spire` namespace.
If you like to change the default namespace,
make sure to use the actual name during the next steps of the deployment.

```console
export PROJECT=spire
oc new-project "$PROJECT" --description="My TSI Spire agent project on OpenShift" 2> /dev/null
```

### Setup information about SPIRE Server
For every cluster hosting SPIRE agents,
including the remote clusters,
define the access to the SPIRE server as it was output in the previous step:
```console
export SPIRE_SERVER=spire-server-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff-0000.us-south.containers.appdomain.cloud
```

Capture the `spire-bundle` ConfigMap
in cluster where Tornjak and SPIRE Server are deployed.
This script changes the namespace to `spire`:
```console
kubectl -n tornjak get configmap spire-bundle -oyaml | kubectl patch --type json --patch '[{"op": "replace", "path": "/metadata/namespace", "value":"spire"}]' -f - --dry-run=client -oyaml > spire-bundle.yaml
```

In every namespace where SPIRE agents will be deployed,
including the remote clusters,
deploy `spire-bundle` ConfigMap:

```console
oc -n spire apply -f spire-bundle.yaml
```

### Run SPIRE agent installation

Execute the installation script to get the most up to date syntax:

```
utils/install-open-shift-spire.sh

-c CLUSTER_NAME must be provided
Install SPIRE agent and workload registrar for TSI

Syntax: utils/install-open-shift-spire.sh -c <CLUSTER_NAME> -s <SPIRE_SERVER> -t <TRUST_DOMAIN> -p <PROJECT_NAME>

Where:
  -c <CLUSTER_NAME> - name of the OpenShift cluster (required)
  -s <SPIRE_SERVER> - SPIRE server end-point (required)
  -r <REGION>       - region, geo-location (required)
  -t <TRUST_DOMAIN> - the trust root of SPIFFE identity provider, default: spiretest.com (optional)
  -p <PROJECT_NAME> - OpenShift project [namespace] to install the Server, default: spire-server (optional)
```

Include the required values `CLUSTER_NAME`, `SPIRE_SERVER`, and `TRUST_DOMAIN`. Make sure they correspond to values from Step 1.

```
utils/install-open-shift-spire.sh -c space-x01 -s $SPIRE_SERVER -r us-east -t openshift.space-x.com
```
Sample output:
```
jq client setup properly
oc client setup properly
Kubernetes server version is correct
helm client v3 installed properly
ibmcloud oc installed properly
spire                                                             Active
spire project already exists.
Do you want to re-install it? [y/n]

Re-installing spire project
release "spire" uninstalled
securitycontextconstraints.security.openshift.io "spire-agent" deleted
serviceaccount "spire-agent" deleted
project.project.openshift.io "spire" deleted
spire                                                             Terminating
Waiting for spire removal to complete
Already on project "spire" on server "https://c107-e.us-south.containers.cloud.ibm.com:32643".
configmap/spire-bundle created
serviceaccount/spire-agent created
group.user.openshift.io/spiregroup added: "spire-agent"
securitycontextconstraints.security.openshift.io/spire-agent created
securitycontextconstraints.security.openshift.io/spire-agent added to: ["system:serviceaccount:spire:spire-agent"]
securitycontextconstraints.security.openshift.io/privileged added to: ["system:serviceaccount:spire:spire-agent"]
NAME: spire
LAST DEPLOYED: Wed Apr 28 16:19:29 2021
NAMESPACE: spire
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
The installation of the SPIRE Agent and Workload Registrar for
Universal Trusted Workload Identity Service has completed.

    Cluster name: space-x01
    Trust Domain: openshift.space-x.com
    Namespace:    spire
    OpenShift mode: true

  SPIRE info:
      Spire Server address:  spire-server-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff-0000.us-south.containers.appdomain.cloud:443
      Spire Agent image: gcr.io/spiffe-io/spire-agent:0.12.1
      Spire Registrar image: gcr.io/spiffe-io/k8s-workload-registrar:0.12.1


To enable Workload Registrar, create an entry on Tornjak UI:
1. find out what node the registrar is running on:
    kubectl -n spire get pods -o wide
2. get the SPIFFE ID of the agent for this node (Tornjak -> Agents -> Agent List)
3. create Entry (Tornjak -> Entries -> Create Entry) using appropriate Agent
SPIFFE ID as Parent ID:

SPIFFE ID:
  spiffe://openshift.space-x.com/space-x01/workload-registrar
Parent ID:
  spiffe://openshift.space-x.com/spire/agent/k8s_psat/space-x01/xxx
Selectors:
  k8s:sa:spire-k8s-registrar,k8s:ns:spire,k8s:container-name:k8s-workload-registrar
* check Admin Flag


  Chart Name: spire.
  Your release is named spire.

To learn more about the release, try:

  $ helm status spire
  $ helm get all spire

Next, login to the SPIRE Server and register the Workload Registrar to gain admin access to the server.

oc exec -it spire-server-0 -n tornjak -- sh
```

## Validate the installation
Check if all the components were properly deployed.
First, the `tornjak` project:

```
oc project tornjak
oc get po
NAME             READY   STATUS    RESTARTS   AGE
spire-server-0   3/3     Running   0          48m
trusted-service-identity$oc get routes
NAME                 HOST/PORT                                                                                               PATH   SERVICES       PORT     TERMINATION     WILDCARD
oidc                 oidc-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff-0000.us-south.containers.appdomain.cloud                  spire-oidc     https    edge            None
spire-server         spire-server-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff-0000.us-south.containers.appdomain.cloud          spire-server   grpc     passthrough     None
tornjak-http         tornjak-http-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff-0000.us-south.containers.appdomain.cloud          tornjak-http   t-http                   None
tornjak-mtls         tornjak-mtls-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff-0000.us-south.containers.appdomain.cloud          tornjak-mtls   t-mtls   passthrough     None
tornjak-tls          tornjak-tls-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff-0000.us-south.containers.appdomain.cloud           tornjak-tls    t-tls    passthrough     None
```
Now verify the deployment in the `spire` project:
```
oc project spire
oc get po
NAME                               READY   STATUS    RESTARTS   AGE
spire-agent-222kh                  1/1     Running   0          36m
spire-agent-6l9tf                  1/1     Running   0          36m
spire-agent-tgbmn                  1/1     Running   0          36m
spire-registrar-85fcc94797-v9q6w   1/1     Running   0          36m

```
All looks good.

The next step is [registering The Workload Registrar with the SPIRE Server](./spire-workload-registrar.md#register-workload-registrar-with-the-spire-server).
