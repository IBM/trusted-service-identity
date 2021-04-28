# Deploying Tornjak on OpenShift
This tutorial demonstrates the steps required to deploy Tornjak elements on OpenShift platform. To see instructions for installing on non-OpenShift platform, please see the following documentation on [deploying Tornjak with helm charts](./spire-helm.md).


## Prerequisites
The following installation was tested with:
* Red Hat OpenShift 4.5 +
* Kubernetes version 1.18 +


Tutorial requirements:
* [git client](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
* [helm3 client](https://helm.sh/docs/intro/install/)

When deploying on OpenShift, in addition to above the tutorial requires:
* [ibmcloud client](https://cloud.ibm.com/docs/cli?topic=cli-getting-started)
* [open shift client](https://cloud.ibm.com/docs/openshift?topic=openshift-openshift-cli)
* [jq parser](https://stedolan.github.io/jq/)


## Deploy on OpenShift
For this tutorial we will use OpenShift cluster running in IBM Cloud. To get a test ROKS (Red Hat OpenShift on Kubernetes) cluster in IBM Cloud follow the steps outlined here: https://www.ibm.com/cloud/openshift

Deployment of Tornjak Server on OpenShift in IBM Cloud is rather simple. Assuming all the OpenShift prereqs are satisfied, the installation can be done using provided scripts.
First setup the OpenShift environment using admin privileges.

```console
export KUBECONFIG=<open-shift configuration>.yaml
```

Then test the connection:

```console
oc get config
oc get nodes
```

## Step 1. Installing Tornjak Server with SPIRE on OpenShift

We should be ready to execute the installation now. Execute the script to get the most recent syntax.

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
```

Include the `CLUSTER_NAME` and the `TRUST_DOMAIN` as parameters. If you like to install in namespace other than “tornjak” pass the namespace with “-p” flag.

To use “--oidc” please refer to our separate [OIDC document](./spire-oidc-tutorial.md).

This script detects a previous installation of Tornjak and prompts the user if the uninstallation is required.

Sample execution:
```
utils/install-open-shift-tornjak.sh -c space-x.01 -t openshift.space-x.com
```
This scripts takes care of the namespaces/project creation, sets up appropriate permissions, sets up the public access via Ingress, defines HTTP, TLS and mTLS access points and displays all the relevant information at the end.

Sample output:
```
The installation of the Tornjak with SPIRE Server for
Universal Trusted Workload Identity Service has completed.

      Cluster name: space-x.01
      Trust Domain: openshift.space-x.com
      Tornjak Image: tsidentity/tornjak-spire-server:0.12.1
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

Installation of the Tornjak and SPIRE server has completed. We will use information output by the script for the next steps.
We need the `SPIRE_SERVER` value and URLs for accessing Tornjak server (HTTP, TLS or mTLS, depending on the needs).

Now we can move on to the SPIRE Agents deployment

## Step 2. Installing SPIRE Agents on OpenShift
Define the access to the SPIRE server as shown above:
```console
export SPIRE_SERVER=spire-server-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff-0000.us-south.containers.appdomain.cloud
```
Execute the script to get the most recent syntax:

```
utils/install-open-shift-spire.sh

-c CLUSTER_NAME must be provided
Install SPIRE agent and workload registrar for TSI

Syntax: utils/install-open-shift-spire.sh -c <CLUSTER_NAME> -s <SPIRE_SERVER> -t <TRUST_DOMAIN> -p <PROJECT_NAME>

Where:
  -c <CLUSTER_NAME> - name of the OpenShift cluster (required)
  -s <SPIRE_SERVER> - SPIRE server end-point (required)
  -t <TRUST_DOMAIN> - the trust root of SPIFFE identity provider, default: spiretest.com (optional)
  -p <PROJECT_NAME> - OpenShift project [namespace] to install the Server, default: spire-server (optional)
```

Include the required values `CLUSTER_NAME`, `SPIRE_SERVER` and `TRUST_DOMAIN`. Make sure they correspond to values from Step 1.

```
utils/install-open-shift-spire.sh -c space-x.01 -s $SPIRE_SERVER -t openshift.space-x.com
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
project.project.openshift.io "spire" deleted
spire                                                             Terminating
Waiting for spire removal to complete
spire                                                             Terminating
Waiting for spire removal to complete
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
LAST DEPLOYED: Wed Apr 21 14:49:36 2021
NAMESPACE: spire
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
The installation of the SPIRE Agent and Workload Registrar for
Universal Trusted Workload Identity Service has completed.

      Cluster name: space-x.01
      Trust Domain: openshift.space-x.com

  SPIRE info:
      Spire Address:  spire-server-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff6a94-0000.us-south.containers.appdomain.cloud:443
      Spire Registrar Image: gcr.io/spiffe-io/k8s-workload-registrar:0.12.1
      Spire Agent Image: gcr.io/spiffe-io/spire-agent:0.12.1

    Chart Name: spire.
    Your release is named spire.

To learn more about the release, try:

  $ helm status spire
  $ helm get all spire

Next, login to the SPIRE Server and register the Workload Registrar
to gain admin access to the server.

oc exec -it spire-server-0 -n tornjak -- sh
```

Once the agents deployment is completed move on to section Register Workload Registrar with the SPIRE Server
