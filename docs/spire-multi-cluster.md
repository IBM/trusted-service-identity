# Deploying Tornjak in multi-cluster environment
This document describes the steps required to setup Tornjak with SPIRE Server
providing identities for multiple clusters.

This assumes the Tornjak Server is already deployed as described in
[SPIRE with Helm](./spire-helm.md) or [SPIRE on OpenShift](./spire-on-openshift.md)
documents.

Tornjak Server and all the remote cluster must use the same trust domain. E.g:
```
trust_domain = "openshift.space-x.com"
```

For this example we would use the following clusters:
* `space-x01` - local cluster, with public Ingress access. Here we run Tornjak/SPIRE
Server under `tornjak` namespace, and local SPIRE agents.
* `space-x02` - remote cluster (OpenShift)
* `kube-01` - remote cluster (standard Kubernetes)

## Step 1. Gather all KUBECONFIGs from the remote servers.
SPIRE server attests the remote agents by verifying the KUBECONFIG configuration.
Therefore, for every remote cluster, other then the cluster hosting the Tornjak,
we need KUBECONFIG for this cluster.

Gather the KUBECONFIG for every remote cluster
and output them into individual files
using  `kubectl config view --flatten`:

```
export KUBECONFIG=....
export CLUSTERNAME=....
mkdir /tmp/kubeconfigs
kubectl config view --flatten > /tmp/kubeconfigs/$CLUSTERNAME
```

In our example we will have the following:
```
/tmp/kubeconfigs/space-x02
/tmp/kubeconfigs/kube-01
```

Then using these individual files, create a secret in Tornjak cluster.
_Note_: don't use special characters, stick to alphanumerics.

```console
kubectl -n tornjak create secret generic kubeconfigs --from-file=/tmp/kubeconfigs
```

## Step 2. Update SPIRE Server configuration.
Update the SPIRE server configuration, by extending the NodeAttestor "k8s_psat"
arguments.

For all remote servers we need `kube_config_file` that contains its cluster KUBECONFIG.
We don't need this for the local cluster.

We assume all the SPIRE agent are deployed in `spire` namespace
under `spire-agent` service-account,
otherwise change the configuration accordingly:

Update the spire-server ConfigMap:

```console
kubectl -n tornjak edit configmap spire-server
```

```yaml
NodeAttestor "k8s_psat" {
  plugin_data {
      clusters = {
          "space-x01" = {
              service_account_whitelist = ["spire:spire-agent"]
          },
          "space-x02" = {
              service_account_whitelist = ["spire:spire-agent"]
              kube_config_file = "/tmp/kubeconfigs/space-x02"
          },
          "kube-01" = {
              service_account_whitelist = ["spire:spire-agent"]
              kube_config_file = "/tmp/kubeconfigs/kube-01"
          },
      }
  }
}
```

## Step 3. Modify SPIRE Server StatefulSet deployment
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
- mountPath: /tmp/kubeconfig
  name: kubeconfigs
...
volumes:
- name: kubeconfigs
  secret:
    defaultMode: 420
    secretName: kubeconfigs
```

Then restart the SPIRE/Tornjak pod

```console
kubectl -n tornjak delete po spire-server-0
```

Verify if Tornjak/SPIRE server is running well, check the logs and make sure you
can connect to Tornjak dashboard.

## Step 4. Configure remote agents
This work has to be done in every remote cluster.

Gather from Tornjak server the `spire-bundle` that contains the certificates.

```console
kubectl -n tornjak get spire-bundle -oyaml > spire-bundle.yaml
```
Edit the file by changing the namespace from `tornjak` to `spire`
and then update the `spire-bundle` on every remote cluster:

```console
kubectl -n spire apply -f spire-bundle.yaml
```

Update the SPIRE Agents configuration:
```console
kubectl -n spire edit configmap spire-agent
```
* make sure all the clusters point to the same Tornjak server via public
Ingress.
* make sure `trust_domain` is the same as Tornjak's
* make sure the provided cluster corresponds to the values defined earlier

```
data:
  agent.conf: |
    agent {
      data_dir = "/run/spire"
      log_level = "DEBUG"
      server_address = "spire-server-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff6a94-0000.us-south.containers.appdomain.cloud"
      server_port = "443"
      socket_path = "/run/spire/sockets/agent.sock"
      trust_bundle_path = "/run/spire/bundle/bundle.crt"
      trust_domain = "openshift.space-x.com"
    }
    plugins {
      NodeAttestor "k8s_psat" {
        plugin_data {
          cluster = "space-x02"
        }
      }
```
Restart the agents:
```consle
kubectl -n spire get pods
kubectl -n spire delete pod <pod-name>
```
## Step 5. Configure all workload registrars
Here we need to define format of the SVIDs created by the registrars.

The easiest is to create a individual configuration files for every cluster.
This configuration creates the following format:
```
 "region/{{.Context.Region}}/cluster_name/{{.Context.ClusterName}}/ns/{{.Pod.Namespace}}/sa/{{.Pod.ServiceAccount}}/pod_name/{{.Pod.Name}}"
 ```
And this references the context provided in the configuration file as well.
The template can reference any value that is included in context map.
Here is the list of available, self-explanatory Pod arguments:
* Pod.Name
* Pod.UID
* Pod.Namespace
* Pod.ServiceAccount
* Pod.Hostname
* Pod.NodeName

Here is an example for `space-x02` cluster. Similar configuration applies to
`space-x01` and `kube-01`

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: k8s-workload-registrar
  namespace: spire
data:
  registrar.conf: |
    log_level = "debug"
    mode = "crd"
    trust_domain = "openshift.space-x.com"
    # enable when direct socket access to SPIRE Server available:
    # server_socket_path = "/run/spire/sockets/registration.sock"
    agent_socket_path = "/run/spire/sockets/agent.sock"
    server_address = "spire-server-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff6a94-0000.us-south.containers.appdomain.cloud:443"
    cluster = "space-x02"
    # enable for label based registration:
    # pod_label = ""
    # enable for annotation based registration:
    # pod_annotation = ""
    identity_template = "region/{{.Context.Region}}/cluster_name/{{.Context.ClusterName}}/ns/{{.Pod.Namespace}}/sa/{{.Pod.ServiceAccount}}/pod_name/{{.Pod.Name}}"
    identity_template_label = "identity_template"
    context {
      Region = "us-east"
      ClusterName = "space-x02"
    }
```

Please note that `identity_template_label = "identity_template"`, we will use this
during the workload deployment.
If this parameter is omitted or set to `""`, the registrar will process ALL the
containers in the cluster.

Restart the workload registrar pod:

```console
kubectl -n spire get pods
kubectl -n spire delete <registrar-pod-name>
```
Verify if pod created properly, then registar it with SPIRE Server as described
in [spire-workload-registrar.md](spire-workload-registrar.md)


## Step 6. Create a sample workload:

Create standard deployment. Make sure the pod contains a label as specified in the
registrar configuration and it is set to `true`:
`identity_template: "true"`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mars-mission1
  labels:
    app: mars-mission1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mars-mission1
  template:
    metadata:
      labels:
        app: mars-mission1
        identity_template: "true"
    spec:
      containers:
        - name: mars-mission1-main
          image: us.gcr.io/scytale-registry/aws-cli:latest
          command: ["sleep"]
          args: ["1000000000"]
```

## Helpful Hints
### Delete mistakenly created `spiffeid`s
In `crd` mode, registar creates `spiffeid` custom resources for every processes
pod. To cleanup mistakenly created ones, you can use the following trick.

Make sure the registrar is running correctly, able to communicate with SPRIRE,
and it is using valid `identity_template_label` preventing new `spiffeid`s to be created.

List spiffeids and iterate through their namespaces:

```console
kubectl get spiffeid --all-namespaces
export NS=
kubectl -n $NS delete spiffeid $(kubectl -n $NS get spiffeid | awk '{print $1}' )
```

### Manual registrar registration with SPIRE:
Find what host registrar is running on, find the agent on that host, then register
by via Tornjak UI, `Create Entry`:

Selectors:
```
k8s:sa:spire-k8s-registrar,k8s:ns:spire,k8s:container-name:k8s-workload-registrar
```

or connect to SPIRE pod:
```console
kubectl -n tornjak exec -it spire-server-0 -- sh
```

```console
cd bin
./spire-server entry create -admin \
-selector k8s:sa:spire-k8s-registrar \
-selector k8s:ns:spire \
-selector k8s:container-name:k8s-workload-registrar  \
-spiffeID spiffe://openshift.space-x.com/space-x03/registrar \
-parentID spiffe://openshift.space-x.com/spire/agent/k8s_psat/space-x03/4405c9fb-442e-495c-ba56-936adf1489fd \
-registrationUDSPath /run/spire/sockets/registration.sock

./spire-server entry show -registrationUDSPath /run/spire/sockets/registration.sock
```
