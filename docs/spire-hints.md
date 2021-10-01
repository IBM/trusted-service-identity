# Debugging, Hints and Tips for Solving Common Problems
Here is a collection of various tips and hints for debugging
Universal Workload Identity deployment
with SPIRE and Tornjak

The hints collection is grouped in the following sections:
* [SPIRE Agents](#spire-agents)
* [Workload Registrar](#workload-registrar)
* [SPIRE Server](#spire-server)

## SPIRE Agents

**Problem:**

Agent log file shows an error:
```
time="2021-10-01T15:26:14Z" level=info msg="SVID is not found. Starting node attestation" subsystem_name=attestor trust_domain_id="spiffe://openshift.space-x.com"
time="2021-10-01T15:26:44Z" level=error msg="Agent crashed" error="create attestation client: failed to dial dns:///spire-server-tornjak.space-x05-9d995c4a8c7c5f281ce13d5467ff6a94-0000.us-east.containers.appdomain.cloud:443: context deadline exceeded: connection error: desc = \"transport: authentication handshake failed: x509svid: could not verify leaf certificate: x509: certificate signed by unknown authority (possibly because of \\\"crypto/rsa: verification error\\\" while trying to verify candidate authority certificate \\\"SPIFFE\\\")\""
```

**Description:**

Incorrect keys or certificates required for attestation.
Either `spire-bundle` needs to be refreshed or the `kubeconfigs`
secret updated on the SPIRE server.

**Solution:**
To update the "spire-bundle",
get the `spire-bundle` configmap from the SPIRE server, update the namespace to match the agent cluster, then deploy it there.

On the server:
```console
kubectl -n tornjak get configmap spire-bundle -oyaml | kubectl patch --type json --patch '[{"op": "replace", "path": "/metadata/namespace", "value":"spire"}]' -f - --dry-run=client -oyaml > spire-bundle.yaml
```

On the agent cluster:
```console
kubectl -n spire create -f spire-bundle.yaml
```

In case of the remote clusters, follow steps outline [here](./spire-multi-cluster.md#enable-kubernetes-attestor)

---

**Problem:**

**Description:**

**Solution:**

---

## Workload Registrar

**Problem:**
The workload registrar log shows an error:
```
time="2021-10-01T16:58:15Z" level=debug msg="Watching X.509 contexts"
time="2021-10-01T16:58:15Z" level=error msg="Failed to watch the Workload API: rpc error: code = PermissionDenied desc = no identity issued"
time="2021-10-01T16:58:15Z" level=debug msg="Retrying watch in 30s"
```
**Description:**
The Workload Registrar cannot obtain its own identity because its instance was either:
* never registered with the SPIRE Server
* does not have appropriate admin permissions required to write into the SPIRE Server
* re-created on a different node, with a different Parent ID, then the initial instance, so it needs to be re-registered.

**Solution:**
Register the current instance of the Workload Registrar with the SPIRE Server.
See the [documentation](./spire-workload-registrar.md#register-workload-registrar-with-the-spire-server)

---

**Problem:**

The workload registrar log shows an error:
```
E1001 17:00:27.808343      17 reflector.go:178] pkg/mod/k8s.io/client-go@v0.18.2/tools/cache/reflector.go:125: Failed to list *v1beta1.SpiffeID: the server could not find the requested resource (get spiffeids.spiffeid.spiffe.io)
```

**Description:**

During the previous execution of
`helm uninstall` or `utils/insta-open-shift-x.sh --clean`
there were active `spiffeid` objects that could not be deleted.
Now, successfully executing The Workload Registrar operator was able to delete
the stale `spiffeid` records and then
`spiffeids.spiffeid.spiffe.io` CRD was finalized
and eventually removed.
Now it need to be recreated.

**Solution:**

Either re-run the agents installation again,
or create the CRD manually:

```console
kubectl -n spire create -f charts/spire/templates/spiffeid.spiffe.io_spiffeids.yaml
```
---
**Problem:**

The workload registrar log shows an error:
```
time="2021-10-01T16:50:45Z" level=error msg="Failed to watch the Workload API: rpc error: code = Unavailable desc = connection error: desc = \"transport: Error while dialing dial unix /run/spire/sockets/agent.sock: connect: no such file or directory\""
```
**Description:**

The Workload Registar cannot connect to the SPIRE agent.

**Solution:**

Check the SPIRE agent running on the same node as the Workload Registrar. Fix the SPIRE agent. If the agent was restarted,
give it a minute or two, the connection should be recreated.
Make sure the permissions for accessing the socket are correct.

---

**Problem:**

**Description:**

**Solution:**

---
## SPIRE Server
**Problem:**

**Description:**

**Solution:**

---
