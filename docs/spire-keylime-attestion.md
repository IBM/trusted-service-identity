# Setting up the SPIRE NodeAttestor with Keylime
## Keylime Overview
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

## Attestation Process Overview
We are using existing SPIRE `x509pop` NodeAttestor (x509 proof of possession)
to attest the node:

([server plugin](https://github.com/spiffe/spire/blob/main/doc/plugin_server_nodeattestor_x509pop.md),
[agent plugin](https://github.com/spiffe/spire/blob/main/doc/plugin_agent_nodeattestor_x509pop.md))

* Keylime executes the measured boot attestation based on the list of sha256
reference state of kernel, boot loader etc.
* Once the node is successfully attested by Keylime,
the Keylime server uses remote Keylime agents to securely deliver
`intermediate.key.pem` and `intermediate.cert.pem`
to the attested and verfied node, and then creates and signs
`node.key.pem` and `node.cert.pem` with a short TTL
that stay on the node.
* SPIRE Agents use the `*.pem`s to complete the attestation and register with the
SPIRE Server.
* Keylime continues attesting the nodes and periodically creates new `x509`
* When Keylime fails the attestation, the node is considered compromised and
Keylime stops the `x509` injections.  Next, the Attestation driver bans the compromised agent. Between these two operation, it should make the compromised agent not able to manage identities for the hosted workloads.

The detailed flow is available in [Attestation-demo.pdf](./ppt/Attestation-demo.pdf) deck.

# Dependencies and Pre-reqs
This requires a few updates:
* node re-attestation: https://github.com/spiffe/spire/pull/3031
* short TTL for JWT-SVIDs https://github.com/spiffe/spire/issues/2700
* https://github.com/spiffe/spire/issues/3133
* we have to clean up and open-source the CLI for managing the Keylime operations

## Obtain a Kubernetes cluster with deployed Keylime
We use an internal process for deploying a cluster with Keylime.
Connect to the node that has Keylime server.

## Demo Setup
This example requires x509 certificates. The samples are provided in
[../sample-x509](../sample-x509).
Instructions for creating your own are available [here](x509-create.md)

If you are already running the SPIRE/Tornjak server,
find the *rootCA.pem*  currently used:

```console
kubectl -n tornjak get secrets sample-x509 -o jsonpath='{.data'} | jq -r '."rootCA.pem"' | base64 -d
```

Gather the correct keys and certs and put them in
`trusted-service-identity/x509` directory.


## Deploy the x509 keys to all the nodes


Check the status of the current Keylime nodes and make sure they are all in
`verified` state:

```console
keylime-op -u /root/undercloud.yml -m /root/mzone.yml -o status
```
Sample response:
```json
{
  "composite": {
    "small7-agent0": {
      "status": "verified"
    },
    "small7-agent1": {
      "status": "verified"
    },
    "small7-agent2": {
      "status": "verified"
    },
    "small7-agent3": {
      "status": "verified"
    },
    "small7-agent4": {
      "status": "verified"
    }
  },
  "summary": {
    "verified": 5
  },
  "concise": "verified"
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

## Install SPIRE Agents
When everything is good, setup the `spire-bundle` from the SPIRE Server
and execute the helm installation.

Capture the spire-bundle on the SPIRE Server:

```console
kubectl -n tornjak get configmap spire-bundle -oyaml | kubectl patch --type json --patch '[{"op": "replace", "path": "/metadata/namespace", "value":"spire"}]' -f - --dry-run=client -oyaml > spire-bundle.yaml
```

Bring it to the newly created cluster with deployed x509 keys and install:
```console
kubectl create ns spire
kubectl create -f spire-bundle.yaml
```


To get SPIRE info from the Server: 
```console
kubectl -n tornjak get routes | grep spire-server
```

Setup the CLUSTER_NAME, REGION variables, and location of your SPIRE_SERVER.
```
cd ~/trusted-service-identity/
export CLUSTER_NAME=css
export REGION=us-ykt
export SPIRE_SERVER=
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

Check the current status of the node:
```console
keylime-op -u /root/undercloud.yml -m /root/mzone.yml -o status
```

Obtain the access to Tornjak e.g.
```console
export TORNJAK="http://tornjak-http-tornjak.spire-01-0000.us-east.containers.appdomain.cloud"
```

Run the Attestation Driver:
```console
cd trusted-service-identity/utils/

./keylime_monitor.sh &
```



## Enable Measured Boot Attestation
Create the initial, correct kernel and boot loader reference state.
These values are calculated by CI system and represent sha256 sums
based on the kernel, boot loader etc etc.

```console
cat > mbref.json <<EOF
{
  "tag": "sdebuilder_kube_628aa5e_ubuntu_focal_amd64",
  "shim_authcode_sha256": "0xdbffd70a2c43fd2c1931f18b8f8c08c5181db15f996f747dfed34def52fad036",
  "grub_authcode_sha256": "0x412ce775fe05b194ce64441443aa721ad8b7dedb8e4f5e40481633d596d5b842",
  "kernel_authcode_sha256": "0x03910cd3da2eefac39ce0bedf071dadf4e6b0a536121bd8e1f41f751aae3925e",
  "kernel_plain_sha256": "0x5c6120cddb77ba236333081e69ac4f790d6983a899047df0e728bf1ab2b84afc",
  "initrd_plain_sha256": "0xa1457f95224f364ab3c12f5ce24190d8c5cc0ba2e17259a2556e3a860259a96c"
}
EOF
```

So now, we can invoke the following commands to enable measure boot attestation:

```console
keylime-op -u /root/undercloud.yml -m /root/mzone.yml -o mba-bundle-clear
keylime-op -u /root/undercloud.yml -m /root/mzone.yml -o mba-bios-clear
keylime-op -u /root/undercloud.yml -m /root/mzone.yml -o mba-sb-clear
keylime-op -u /root/undercloud.yml -m /root/mzone.yml -o mba-bundle-append --refstate "$(cat mbref.json)"
```

These commands need to be run before we deploy the x509 certificates.
x509 should be deployed only if the attestation was successful (_verified_).

```console
keylime-op -u /root/undercloud.yml -m /root/mzone.yml -o status
{
  "composite": {
    "small7-agent0": {
      "status": "verified"
    },
    "small7-agent1": {
      "status": "verified"
    },
    "small7-agent2": {
      "status": "verified"
    },
    "small7-agent3": {
      "status": "verified"
    },
    "small7-agent4": {
      "status": "verified"
    }
  },
  "summary": {
    "verified": 5
  },
  "concise": "verified"
}
```




Now, let's try to corrupt TPM PCRs
```console
# Corrupt the TPM PCRs
ssh small7-agent3
# then, once inside execute this:
docker exec -it keylime_agent tpm2_pcrextend 4:sha1=f1d2d2f924e986ac86fdf7b36c94bcdf32beec15,sha256=b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c
```
This command will mess up the TPM by adding a random value to its PCRs.
The next attestation will fail, because the TPM no longer correctly authenticates the boot log

Check again the current status of the node:
```console
keylime-op -u /root/undercloud.yml -m /root/mzone.yml -o status
```

Reboot the node to reset the PCRs
```console
ssh small7-agent3 reboot
```
