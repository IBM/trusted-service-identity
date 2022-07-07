# Deploying Tornjak in multi-cluster environment
This document describes the steps to enable support for multiple clusters.
The workloads and SPIRE agents are deployed in multiple clusters,
all managed by a single Tornjak/SPIRE Server.

![multi-cluster](imgs/multi_cluster.jpg)

This document describes steps for:
* [deploying multi-cluster environments](#deploying-multi-cluster-environment)
* [adding multi-cluster support to an existing deployment](#adding-multi-cluster-support-to-an-existing-deployment)

## Deploying Tornjak server in multi-cluster environment
Tornjak Server and all the remote clusters must use the same trust domain. E.g:
```
trust_domain = "openshift.space-x.com"
```
<!-- For this example we would use the following clusters:
* `openshift-x01` - [OpenShift cluster in IBM Cloud](https://www.ibm.com/cloud/openshift),
with public Ingress access.
Here we run the Tornjak/SPIRE Server in `tornjak` namespace,
and SPIRE agents in `spire` namespace.
* `openshift-x02` - [OpenShift cluster in IBM Cloud](https://www.ibm.com/cloud/openshift)
to host workloads and SPIRE agents in `spire` namespace.
* `kubeibm-01`    - [standard Kubernetes in IBM Cloud](https://www.ibm.com/cloud/kubernetes-service)
to host workloads and SPIRE agents in `spire` namespace.
* `aws-eks-01`     - [AWS EKS](https://aws.amazon.com/eks/)
to host workloads and SPIRE agents in `spire` namespace. -->


### Attesting the remote clusters
In order to be trusted by the SPIRE Server,
all remote agents must be attested.
SPIRE offers node attestors for some of the Cloud providers,
like Amazon EKS, Microsoft Azure and Google GCP.
For others we can use Kubernetes attestor,
which is using [portable "KUBECONFIG" files](#step-1a-capture-the-portable-kubeconfig-files).

Configurations below shows various scenarios that depend on
the deployment type of the remote servers.
Multiple attestors can be used concurrently,
depending on the needs.

---
### Enable AWS node attestor
* Tornjak/SPIRE server
To use AWS node_attestor, we need to provide the following values in
[Tornjak helm chart configuration file](../charts/tornjak/values.yaml):
```yaml
aws_iid:
  access_key_id: "ACCESS_KEY_ID"
  secret_access_key: "SECRET_ACCESS_KEY"
  skip_block_device: true
```
Procedures for obtaining these values are [here](https://docs.aws.amazon.com/general/latest/gr/aws-sec-cred-types.html)

For more information about this plugin configuration see the
[attestor documentation](https://github.com/spiffe/spire/blob/main/doc/plugin_server_nodeattestor_aws_iid.md)

* SPIRE Agents:
To use AWS node_attestor, we need to provide the following value in
[spire helm chart configuration file](../charts/spire/values.yaml):
```yaml
aws: true
```

Or add the `--set "aws=true"` flag to the helm command:
```console
helm install --set "spireServer.address=$SPIRE_SERVER" \
--set "spireServer.port=$SPIRE_PORT"  --set "namespace=$AGENT_NS" \
--set "clustername=$CLUSTERNAME" --set "region=us-east" \
--set "trustdomain=openshift.space-x.com" \
--set "aws=true" \
spire charts/spire --debug
```

---
### Enable Azure node attestor
**TBD**

For more information about this plugin configuration see the
[attestor documentation](https://github.com/spiffe/spire/blob/main/doc/plugin_server_nodeattestor_azure_msi.md)

---
### Enable GCP node attestor
**TBD**

For more information about this plugin configuration see the
[attestor documentation](https://github.com/spiffe/spire/blob/main/doc/plugin_server_nodeattestor_gcp_iit.md)

---
### Enable Kubernetes attestor
When none of the cloud specific attestors is available,
we can use Kubernetes attestor (`k8s_psat`).
SPIRE server attests the remote Kubernetes nodes by verifying the KUBECONFIG configuration.
Therefore, for every remote cluster,
other then the cluster hosting the Tornjak,
we need KUBECONFIG information.

#### Step 1a. Capture the portable KUBECONFIG files
Gather the portable KUBECONFIGs for every remote cluster
and output them into individual files
using  `kubectl config view --flatten`.
Make sure to use `--flatten` flag as it makes the output portable
(includes all the required certificates).

Run this in every remote cluster:
```console
export KUBECONFIG=....
export CLUSTER_NAME=....
mkdir /tmp/kubeconfigs
kubectl config view --flatten > /tmp/kubeconfigs/$CLUSTER_NAME
```

For example, to support 2 remote clusters
`cluster1` and `cluster2`
we will have the following files:
```
/tmp/kubeconfigs/cluster1
/tmp/kubeconfigs/cluster2
```

#### Step 1b. Create secret in SPIRE server cluster
Then using these individual files,
create one secret in `tornjak` project,
where we will deploy SPIRE server.
_Note_: don't use special characters, stick to alphanumerics.

```console
kubectl -n tornjak create secret generic kubeconfigs --from-file=/tmp/kubeconfigs
```
This has to be done before executing the Helm deployment.

If you ever need to update the existing credentials,
create new files, and then run:

```console
kubectl -n tornjak create secret generic kubeconfigs --from-file=/tmp/kubeconfigs --save-config --dry-run=client -o yaml | kubectl -n tornjak apply -f -
```

This change requires SPIRE server restart, but not the agents.


#### Step 1c. Update the Tornjak helm charts
Once the secret is created, we need to update the helm charts
to support the Kuberenetes attestor (`k8s_psat`).

Update the content of the
[charts/tornjak/values.yaml](./charts/tornjak/values.yaml) file.
Modify entries for `attestors\k8s_psat\remoteClusters`.
Include `name` for every remote cluster that is using Kubernetes attestation.
If `namespace` and `serviceAccount` are not provided,
it defaults to:
```
namespace: spire
serviceAccount: spire-agent
```
Here is a sample configuration:

```yaml
attestors:
  k8s_psat:
    remoteClusters:
    - name: cluster1
      namespace: spire
      serviceAccount: spire-agent
    - name: cluster2
    - name: cluster3
      namespace: spire
      serviceAccount: spire-agent
```
---
### Install Tornjak Server with the helm charts
Then follow the standard installation as shown in
[helm](./spire-helm.md#step-1-deploy-tornjak-with-a-spire-server), [OpenShift](./spire-on-openshift.md#step-1-installing-tornjak-server-with-spire-on-openshift)
or [OIDC](./spire-oidc-tutorial.md)
deployments.

### Install SPIRE Agents with the helm charts
**Reminder:**  all the remote clusters must use the same trust domain
as the SPIRE Server.

Follow the standard procedure for deploying SPIRE Agents,
as described in
[helm charts](./spire-helm.md#step-2-deploy-a-spire-agents)
of [OpenShift](./spire-on-openshift.md#step-2-installing-spire-agents-on-openshift)
Agents deployment.

---

## Adding multi-cluster support to an existing deployment
This part describes the steps required to extend the existing
Tornjak/SPIRE Server to support multiple clusters.

It assumes the Tornjak Server is already deployed as described in
[SPIRE with Helm](./spire-helm.md)
or [SPIRE on OpenShift](./spire-on-openshift.md)
documents.

### Update SPIRE Server configuration.
* Review the steps outline above for using individual attestors,
whether cloud specific or Kubernetes one `k8s_psat`.
* Create the `kubeconfigs` secret if needed.
* Update the SPIRE server configuration accordingly:
```console
kubectl -n tornjak edit configmap spire-server
```
Here is a sample configuration:

```yaml
NodeAttestor "k8s_psat" {
  plugin_data {
      clusters = {
          "tsi-kube01" = {
              service_account_allow_list = ["spire:spire-agent"]
              kube_config_file = "/run/spire/kubeconfigs/tsi-kube01"
          }
      }
  }
}
```
* If using the secret for `k8s_psat` attestor,
modify the SPIRE Server StatefulSet deployment
Here we want to make the KUBECONFIGs available to the SPIRE server.
We will mount the secret to the SPIRE server instance.
Edit the spire-server StatefulSet
and look for `spire-server` container,
then add the volume mount reference,
and create a volume from the `kubeconfigs` secret.

```console
kubectl -n tornjak edit statefulset spire-server
```

This might look like this:
```yaml
...
name: spire-server
...
volumeMounts:
- mountPath: /run/spire/kubeconfigs
  name: kubeconfigs
...
volumes:
- name: kubeconfigs
  secret:
    defaultMode: 0400
    secretName: kubeconfigs
```

Then restart the SPIRE/Tornjak pod

```console
kubectl -n tornjak delete po spire-server-0
```

Verify if Tornjak/SPIRE server is running well, check the logs and make sure you
can connect to the Tornjak dashboard.

## Configure remote agents
Deploy the `spire-bundle` ConfigMap to all the agent clusters,
as described in [helm document](./spire-helm.md#separate-or-multi-cluster)

### AWS Clusters
For all the remote clusters hosted in AWS,
you have to update the SPIRE Agent configuration
```console
kubectl -n spire edit configmap spire-agent
```

Add the `NodeAttestor "aws_iid"` to the list of plugins.

```
plugins {
  NodeAttestor "k8s_psat" {
    plugin_data {
      cluster = "cluster-name"
    }
  }
  NodeAttestor "aws_iid" {
      plugin_data {}
  }
}
```
Generally, no plugin data is needed in AWS, and the above configuration should be used. For testing or non-standard AWS environments, you may need to specify the Metadata endpoint.
See [more here](https://github.com/spiffe/spire/blob/main/doc/plugin_agent_nodeattestor_aws_iid.md)

Restart the agents:
```console
kubectl -n spire get pods
kubectl -n spire delete pod <pod-name>
```

**Comment:** If you get the following error:
```
time="2021-08-19T16:48:43Z" level=error msg="Agent crashed" error="failed to get SVID: error getting attestation response from SPIRE server: rpc error: code = Internal desc = failed to attest: aws-iid: IID has already been used to attest an agent"
```
Delete the agent object under "Agents"-->"Agent List" using Tornjak UI.
This should remove the SPIRE record and allow the agent to re-register.

Restart the agents.
