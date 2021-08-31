# Tornjak Deployment and Demos
This document describes the list of available documents to deploy and
run various Tornjak demos.

The demos are sorted by complexity,
starting with this simple ones and progressing into more complex.

We suggest running the demos in specified order.

## Tornjak Deployment
There are multiple ways to deploy Tornjak on Kubernetes.
The simplest scenario is when Tornjak and SPIRE server
are deployed in the same cluster as the workloads and SPIRE agents.

### Single cluster on local `minikube` or `kind`
![single cluster on minikube or kind](imgs/single_cluster_local.jpg)

### Single cluster in the Cloud with OpenShift
![single cluster on OpenShift](imgs/single_cluster_openshift.jpg)

### Multi-Cluster deployment
![multi-cluster](imgs/multi_cluster.jpg)

These demos deploy Tornjak Server and SPIRE agents in various scenarios:
1. deploy in a single cluster locally [via helm charts](./spire-helm.md)
2. deploy in IBM Cloud [via helm charts](./spire-helm.md)
3. deploy on [OpenShift in IBM Cloud](./spire-on-openshift.md)
4. [multi-cluster deployment](./spire-multi-cluster.md)
5. [SPIRE agents on AWS](./spire-on-aws.md)

## Tornjak use-cases
These demos showcase various experiments
1. [OIDC Tutorial](./spire-oidc-tutorial.md)
2. [OIDC for Vault](./spire-oidc-vault.md)
3. [AWS S3 storage access via OIDC](./spire-oidc-aws-s3.md)
