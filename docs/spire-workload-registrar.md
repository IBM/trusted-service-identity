# Workload Registrar for SPIRE
The Workload Registrar described in this tutorial is based on the following [documentation](https://github.com/spiffe/spire/tree/main/support/k8s/k8s-workload-registrar)

The Workload Registrar facilitates automatic workload registration within Kubernetes. In our deployment, we use it in "reconcile" mode for Kubernetes pods. It automatically detects all the pods and registers them with SPIRE server by creating new SPIRE Entries. Once entries are created, they will be reconciled by the registrar. Deleting the pod would also remove the SPIRE entry.

The Workload Registrar is deployed by ["spire" helm chart](../charts/spire/) along with SPIRE agents.

We are using "pod_annotation" mode. This means the identity of the pod would be represented by an annotation named "spire-workload-id". See the [example](#create-sample-deployment).
More about this identity schema [here](./identity-schema.md).

## Register Workload Registrar with the SPIRE server.
Workload Registrar will use its own identity to register itself with the SPIRE server. Once registered, it would monitor all the activities in the K8s cluster, register and reconcile the pods with the SPIRE server.

First, we need to create an entry in SPIRE that would represent the Workload Registrar.
This requires few steps:
* find out what node the registrar is running on. This is needed to find out the Parent ID (Agent SVID) of the Agent associated with the same node. Alternatively, we can create individual entries, one per node/agent.

  ```
  kubectl -n spire get pods -o wide

  NAME                               READY   STATUS    RESTARTS   AGE     IP              NODE            NOMINATED NODE   READINESS GATES
  spire-agent-d8s5v                  1/1     Running   0          0h24m   10.38.240.214   10.38.240.214   <none>           <none>
  spire-agent-sd44n                  1/1     Running   0          0h24m   10.38.240.223   10.38.240.223   <none>           <none>
  spire-agent-tms46                  1/1     Running   0          0h24m   10.38.240.226   10.38.240.226   <none>           <none>
  spire-registrar-77ff576ccb-tsr4t   1/1     Running   0          0h24m   172.30.40.199   10.38.240.214   <none>           <none>
  ```
  In this case the registrar is running on the node `10.38.240.214`
* Connect to Tornjak server UI, and list the agents.
Get the SVID (SPIFFE ID) of the agent running on the specific node (as above). You can use the search function.
* Create a new entry `(Select Entries → Create Entry)`
   - and paste the Agent SVID as a `Parent ID`
   - Use the sample string suggested at the end of the helm/OpenShift deployment as `SPIFFE ID` for the registrar:
   ```
   spiffe://openshift.space-x.com/space-x.01/workload-registrar
   ```
   - Use the `selectors` suggested by the installation: e.g:
   ```
   k8s:sa:spire-k8s-registrar,k8s:ns:spire,k8s:container-name:k8s-workload-registrar
   ```
   - Make sure to check the `Admin Flag`, so the registrar gets enough permissions to create new entries.

If everything was fine, we should start seeing new entries, including the agents and the registrar `(Entries → Entry List)`
Otherwise, review the registrar logs.

## Create sample deployment
To see this environment in action, let’s deploy a sample workload with a simple SPIRE client. This example starts a pod that contains SPIRE agent binaries. We can use them to get SPIFFE identity.
Before deploying the client, let’s take a look at the deployment file:
`examples/spire/simple-client.yaml`

There is an annotation that looks like this:
```yaml
metadata:
   annotations:
     spire-workload-id: eu-de/my-cluster/my-ns/my-sa/my-spire-agent-image
```
This annotation corresponds to the identity of the containers and currently, it’s included with the deployment.
More about this identity schema [here](./identity-schema.md).
We are working on a webhook that will dynamically assign a correct SPIFFE identity based on the information obtained from Kubernetes APIs. For this demo, let’s use this annotation example.

Deploy the `simple-spire-client` in the default namespace. Some namespaces might have restriction on the usage of sockets for communicating with the SPIRE agent.

```
kubectl -n default create -f examples/spire/simple-client.yaml
kubectl -n default get pods
```

Once the pod is successfully created, get inside:
```
kubectl -n default exec -it <pod-id> -- sh
```

From inside the container we can now use the SPIRE agent binaries and execute calls to the SPIRE agent:

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