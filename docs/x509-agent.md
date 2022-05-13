# Deploy SPIRE Agent with x509pop (Proof of Possession) Node Attestor for Confidential Computing project

The `x509pop` nodeAttestor plugin attests nodes that have been provisioned with
an x509 identity through an out-of-band mechanism.
It verifies that the certificate is rooted to a trusted set of CAs
and issues a signature based proof-of-possession challenge to the agent plugin
to verify that the node is in possession of the private key.

This document is a second part of the 2 part activity, see [Deploy SPIRE Server with x509pop](./x509.md)

## Pre-install: Get the installation code and sample keys
Obtain the clone of the repo:

```console
git clone https://github.com/IBM/trusted-service-identity.git
git checkout conf_container
```

Sample keys are already created in `sample-x509` directory.


## Deploy SPIRE Agents

### Env. Setup
Setup `KUBECONFIG` for your Kubernetes cluster.

Setup CLUSTER_NAME, REGION and SPIRE
In IBM Cloud, use the script:

```console
utils/get-cluster-info.sh
```

otherwise setup them up directly, for now, use any strings:
```console
export CLUSTER_NAME=
export REGION=
```

Point at the SPIRE Server, this is the server deployed in previous step:
```console
export SPIRE_SERVER=
```

### Deploy the keys
Eventually, the x509 cert will be delivered to the host out-of-bound, but for now, let's pass them as secrets.

```console
# create a namespace:
kubectl create ns spire

# create a secret with keys:
kubectl -n spire create secret generic agent-x509 \
--from-file=key.pem="sample-x509/leaf1-key.pem" \
--from-file=cert.pem="sample-x509/leaf1-crt-bundle.pem"
```

### Deploy `spire-bundle`
Deploy `spire-bundle` obtained from the SPIRE server.

```console
kubectl -n spire create -f spire-bundle.yaml
```

## Install the Spire Agents

If installing on OpenShift:

```console
utils/install-open-shift-spire.sh -c $CLUSTER_NAME -r $REGION -s $SPIRE_SERVER -t openshift.space-x.com
```

If installing in native Kubernetes environment:

```console
helm install --set "spireServer.address=$SPIRE_SERVER" \
--set "namespace=spire" \
--set "clustername=$CLUSTER_NAME" --set "trustdomain=openshift.space-x.com" \
--set "region=$REGION" \
--set "x509=true" \
--set "openShift=false" spire charts/spire --debug
```

## Validate the installation
The number of Spire agents corresponds to the number of nodes:
```console
kubectl -n spire get no
NAME            STATUS   ROLES    AGE   VERSION
10.188.196.81   Ready    <none>   1h    v1.22.8+IKS
10.188.196.82   Ready    <none>   1h    v1.22.8+IKS
kubectl -n spire get po
NAME                               READY   STATUS    RESTARTS   AGE
spire-agent-h9f2j                  1/1     Running   0          11s
spire-agent-s2bjt                  1/1     Running   0          11s
spire-registrar-5bb497cfd8-vpxnl   1/1     Running   0          11s
```

### To cleanup the cluster (removes everything)

```console
utils/install-open-shift-spire.sh --clean
```
