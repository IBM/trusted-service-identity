# Setting up the SPIRE NodeAttestor with Keylime
[Keylime](https://keylime.dev) is an open-source tool,
part of the [CNCF](https://cncf.io/) project,
that provides a highly scalable remote boot attestation
and runtime integrity measurement solution.
Keylime enables users to monitor remote nodes
using a hardware based cryptographic root of trust.

In this example, the Node Attestation is done using Keylime (and TPM),
tying the Workload Identity with Hardware Root of Trust:
* It guarantees the identity of the node beyond any doubt
* It attests the software stack, from booting to the kernel.
We know the firmware, packages, libraries. Enforcement of the software bill of materials (SBOM)
* It measures and enforces the integrity of files (IMA)

Once the node is attested by Keylime, the Keylime agents deliver securely
`intermediate.key.pem` and `intermediate.cert.pem`
to the node, and then create and sign
`node.key.pem` and `node.cert.pem` used by
SPIRE `x509pop` NodeAttestor (x509 proof of possession):
([server plugin](https://github.com/spiffe/spire/blob/main/doc/plugin_server_nodeattestor_x509pop.md),
[agent plugin](https://github.com/spiffe/spire/blob/main/doc/plugin_agent_nodeattestor_x509pop.md))

This example requires x509 certificates. The samples are provided in
[../sample-x509](../sample-x509).
Instructions for creating your own are available [here](x509-create.md)

## Obtain a Kubernetes cluster with deployed Keylime
We use an internal process for deploying a cluster with Keylime.
Connect to the node that has Keylime server.


## Deploy the x509 keys to all the nodes
Obtain the Trusted Service Identity project
```console
cd ~
git clone https://github.com/IBM/trusted-service-identity.git
cd trusted-service-identity
git checkout conf_container
```

Check the status of the current Keylime nodes and make sure they are all in
`verified` state:

```console
keylime-op -u /root/undercloud.yml -m /root/mzone.yml -o status
```
Sample response:
```
{
  "concise": "verified",
  "status": {
    "small7-agent0": "verified",
    "small7-agent1": "verified",
    "small7-agent2": "verified",
    "small7-agent3": "verified",
    "small7-agent4": "verified"
  }
}
```
Execute the key deployment script
```console
cd utils
./deployKeys_keylime.sh
```

Once all the nodes show Keylime agents as verified again, check if the keys
were correctly deployed. Ssh to a hosts:

```console
ssh small7-agent0 "ls -l /run/spire/x509/; cat /run/spire/x509/*"
```

When everything is good, setup the `spire-bundle` and execute the helm installation.

Capture the spire-bundle on the SPIRE Server:

```console
kubectl -n tornjak get configmap spire-bundle -oyaml | kubectl patch --type json --patch '[{"op": "replace", "path": "/metadata/namespace", "value":"spire"}]' -f - --dry-run=client -oyaml > spire-bundle.yaml
```

Bring it to the newly created cluster with deployed x509 keys and install:
```console
kubectl create ns spire
kubectl create -f spire-bundle.yaml
```

Setup the CLUSTER_NAME, REGION variables, and location of your SPIRE_SERVER:

```
cd ~/trusted-service-identity/
export CLUSTER_NAME=css
export REGION=us-ykt
export SPIRE_SERVER=spire-server-tornjak.us-east.containers.appdomain.cloud
```

Execute the SPIRE Agent installation:
```console
helm install --set "spireServer.address=$SPIRE_SERVER" \
--set "namespace=spire" \
--set "clustername=$CLUSTER_NAME" --set "trustdomain=openshift.space-x.com" \
--set "region=$REGION" \
--set "x509=true" \
--set "openShift=false" spire charts/spire --debug
```
