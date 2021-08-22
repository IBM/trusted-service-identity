# Workload Registrar for SPIRE
The Workload Registrar described in this tutorial is based on the following [documentation](https://github.com/spiffe/spire/tree/main/support/k8s/k8s-workload-registrar)

The Workload Registrar facilitates automatic workload registration within Kubernetes.
In our example, we use the "crd" mode to register Kubernetes pods,
and "identity_template" to create custom format of Spiffe IDs
that contain `Region` and `ClusterName` for each deployment.

This Registrar automatically detects all the pods labeled to get identity,
and registers them with SPIRE server, by creating new SPIRE Entries.
Deleting the pod would also remove the SPIRE entry.

The Workload Registrar is deployed by ["spire" helm chart](../charts/spire/) along with SPIRE agents.

## Configure Workload Registrar
The Workload Registrar configuration details are available
[here](https://github.com/spiffe/spire/blob/main/support/k8s/k8s-workload-registrar/README.md#identity-template-based-workload-registration)

The final configuration is created
[here](../charts/spire/templates/k8s-workload-registrar-configmap.tpl)

The format of the SPIFFE Id might have the following format:
```
identity_template = "{{ "region/{{.Context.Region}}/cluster_name/{{.Context.ClusterName}}/ns/{{.Pod.Namespace}}/sa/{{.Pod.ServiceAccount}}/pod_name/{{.Pod.Name}}" }}"
identity_template_label = "identity_template"
context {
  Region = "{{ .Values.region }}"
  ClusterName = "{{ .Values.clustername }}"
}
```

To change this format, modify `identity-template` value.
Make sure the referenced values match `context` map.

The template can reference any value
that is included in the context map
and Pod arguments.
Here is the list of currently available,
self-explanatory Pod arguments:
* Pod.Name
* Pod.UID
* Pod.Namespace
* Pod.ServiceAccount
* Pod.Hostname
* Pod.NodeName


To assign identity to all pods in the cluster,
remove the value for `identity_template_label`.
Otherwise, only the pods with a given label:

```yaml
identity_template: "true"
```
will get their identity.

## Register Workload Registrar with the SPIRE server.
Workload Registrar will use its own identity to register itself with the SPIRE server.
Once registered, it would monitor all the activities in the K8s cluster,
register all the labeled pods with the SPIRE server.

First, we need to create an entry in SPIRE that would represent the Workload Registrar.
This requires few steps:
* Find out what node the registrar is running on. This is needed to find out the Parent ID (Agent SVID) of the Agent associated with the same node. Alternatively, we can create individual entries, one per node/agent.

  ```
  kubectl -n spire get pods -o wide

  NAME                               READY   STATUS    RESTARTS   AGE     IP              NODE            NOMINATED NODE   READINESS GATES
  spire-agent-d8s5v                  1/1     Running   0          0h24m   10.38.240.214   10.38.240.214   <none>           <none>
  spire-agent-sd44n                  1/1     Running   0          0h24m   10.38.240.223   10.38.240.223   <none>           <none>
  spire-agent-tms46                  1/1     Running   0          0h24m   10.38.240.226   10.38.240.226   <none>           <none>
  spire-registrar-77ff576ccb-tsr4t   1/1     Running   0          0h24m   172.30.40.199   10.38.240.214   <none>           <none>
  ```
  In this case the registrar is running on the node `10.38.240.214`

  There are 2 methods to register Workload Registrar:

### Register Workload Registrar using Tornjak UI
* Connect to Tornjak server UI, and list the agents.
Get the SVID (SPIFFE ID) of the agent running on the specific node (as above). You can use the search function.
* In the selected agent row in the table, click on the three dots in the rightmost column under `Workload Attestor Plugin`.  Under `Add WorkLoad Attestor Info→WorkLoad Attestor Plugin`, select Kubernetes, and click `Save & Add`.
* Create a new entry `(Select Entries → Create Entry)`
   - Select the matching Agent SVID as a `Parent ID`
   - Use the sample string suggested at the end of the helm/OpenShift deployment as `SPIFFE ID` for the registrar:
   ```
   spiffe://openshift.space-x.com/mycluster/workload-registrar
   ```
   - Under Selectors Recommendation, select the `selectors` suggested by the installation under `Selectors Recommendation`.  For example, if the installation suggests the following:
   ```
   k8s:sa:spire-k8s-registrar,k8s:ns:spire,k8s:container-name:k8s-workload-registrar
   ```
   check off `k8s:sa`, `k8s:ns`, `k8s:container-name`.  Then under `Selectors`, fill in the suggested values.
   - Make sure to check the `Admin Flag`, so the registrar gets enough permissions to create new entries.
* If you anticipate Workload Registrar pod might get recreated on a different node,
create entries (`workload-registrar1`,`workload-registrar1`...) for every Agent Parent ID.

If everything was fine, we should start seeing new entries, including the agents and the registrar `(Entries → Entry List)`
Otherwise, review the registrar logs.

### Register Workload Registrar manually
Get to the cluster that is hosting the Tornjak/SPIRE Server,
find the `spire-server-0` pod and get inside:

```console
kubectl -n tornjak get pods
kubectl -n tornjak exec -it spire-server-0 exec -- sh
```

List all the agent objects, and find the spiffeID of the agent
that is on the same node as the Registrar. This will be our `parentID`:

```console
/opt/spire/bin/spire-server agent list -registrationUDSPath /run/spire/sockets/registration.sock
```

Now manually create an entry with Admin privileges.
Replace the value of the `mycluster` with actual cluster name
and `agent_spiffe_id` with `parentID` obtained above:

```console
/opt/spire/bin/spire-server entry create -admin \
-selector k8s:ns:spire \
-selector k8s:sa:spire-k8s-registrar \
-selector k8s:container-name:k8s-workload-registrar \
-spiffeID spiffe://openshift.space-x.com/mycluster/workload-registrar1 \
-parentID spiffe://openshift.space-x.com/spire/agent/k8s_psat/agent_spiffe_id \
-registrationUDSPath /run/spire/sockets/registration.sock
```
You can view all the entries:
```console
/opt/spire/bin/spire-server entry show \
-registrationUDSPath /run/spire/sockets/registration.sock
```

or delete them, if needed, using `Entry ID` value:
```console
/opt/spire/bin/spire-server entry delete -entryID 778e71dc-74b7-4899-8d67-2f17ce7604c1 \
-registrationUDSPath /run/spire/sockets/registration.sock
```

## Create sample deployment
To see this environment in action, let’s deploy a sample workload with a simple SPIRE client. This example starts a pod that contains SPIRE agent binaries. We can use them to get SPIFFE identity.
Before deploying the client, let’s take a look at the deployment file:
[examples/spire/simple-client.yaml](../examples/spire/simple-client.yaml)

There is label that looks like this:
```yaml
metadata:
  labels:
    identity_template: "true"
```
This label tells the Registrar to create identity for this pod.
Deploy the `simple-spire-client` in the default namespace.
Some namespaces might have restriction on the usage of sockets
for communicating with the SPIRE agent.

```
kubectl -n default create -f examples/spire/simple-client.yaml
kubectl -n default get pods
```

Once the pod is successfully created, get inside:
```
kubectl -n default exec -it <pod-id> -- sh
```

From inside the container we can use the SPIRE agent binaries
to execute calls to the SPIRE agent:

```console
/opt/spire/bin/spire-agent healthcheck -socketPath /run/spire/sockets/agent.sock
Agent is healthy.
```

We can get all the certificates and store them locally:
```
bin/spire-agent api fetch -write /tmp -socketPath /run/spire/sockets/agent.sock
```

Or get the JWT token with pod’s identity, using audience “client-test”:
```
bin/spire-agent api fetch jwt -audience client-test  -socketPath /run/spire/sockets/agent.sock
```

Since the container successfully obtained its identity, what can we do with it?
See our [“OIDC Tutorial with Vault and AWS S3“](./spire-oidc-tutorial.md) to learn more.


## Helpful Hints
### Delete mistakenly created `spiffeid`s
In `crd` mode, the registrar creates `spiffeid`
custom resources for every processes pod.
To cleanup mistakenly created ones, you can use the following trick.

Make sure the registrar is running correctly,
able to communicate with SPRIRE Server,
and it is configured to use a valid `identity_template_label` preventing new `spiffeid`s to be created for all the pods.

```
identity_template_label="identity_template"
```

List spiffeids and iterate through their namespaces:

```console
kubectl get spiffeid --all-namespaces
export NS=
kubectl -n $NS delete spiffeid $(kubectl -n $NS get spiffeid | awk '{print $1}' )
```
