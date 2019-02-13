# Bootstrap Overview

This document describes the bootstrap process of a cluster that will utilize trusted identity. 
The important points about bootstrapping is ensuring a setup where the keys are accessible to the components, and that they are delivered in a trusted and secure way. This will be the focus of the document.
Bootstrapping of a cluster can be done in 3 different settings of key storage and usage, they are:
1. bootstrapping key on 1 vTPM/TPM as CA per cluster
2. bootstrapping key on per node vTPM/TPM as CA per cluster 
3. bootstrapping key on per node vTPM/TPM per cluster with a central CA

We will first go through how (1) is done. (2) and (3) are incremental steps on top of (1).

## 1. bootstrapping key on 1 vTPM/TPM as CA per cluster


### Provisioning a cluster

The first step of bootstrapping is provisioning. We assume a secure provisioning process with measured and secure boot to ensure that the system is in a trusted initial state. This is a step controlled by the on-premise provider or cloud provider. 

Before installing Trusted Identity, it is important to verify that the setup is secure (ideally with an attestation of measured boot and TPM). Trust can also be established by evidence of a secure provisioning process.

### Installing Trusted Identity

We now assume that we have a cluster provisioned with a kubernetes cluster. We install the trusted identity helm chart deployment, which will create the necessary components of trusted identity in the cluster. 

In deploying the helm chart, we assume that there is components of the orchestration system that validates that the integrity of the deployment.

Part of this process includes a key-server component of TI initializing and setting up of the vTPM/TPM. It will establish ownership of the module and create a RSA key pair. This key pair in this case will act as a CA (this is where it will differ in (3)).

### Binding trust with CA to key server

In order to bind the trust of the CA to the key server, this requires a trusted operator to create the trust binding. This portion of the bootstrap process is about telling the key server which CA is trusted. 

Assuming a trusted key server, a trusted operator obtains the CA from the vTPM/TPM with attesting that it is from that vTPM/TPM. The trusted operator then put the CA in the key server alongside a set of claims that the cluster is required to have (i.e. this CA only can have region:US).

This will allow the key server to validate the tokens that TI generates and prevent spoofing across certain established trust boundaries.


### End of bootstrap

This is the end of the boostrap process, and the regular TI process and system integrity components will continue to uphold the integrity of the system.


## Other setup options (2) and (3)

The other setup options talked about earlier are slight modifications of the bootstrap process. In fact, most of the steps are identitcal, besides generation of the keys in the vTPM/TPM and bootstrapping of trust. Below, we will describe the differences with the above bootstrap process for each of the setups.

### 2. bootstrapping key on per node vTPM/TPM as CA per cluster 

The difference here is that the CA is per node instead of one per cluster. The difference here is that for every node, TI will generate a RSA key pair (each of which will act as a node CA of the cluster). 

In the step of "Binding trust with CA to key server", the trusted operator would perform the same process for a single CA cluster with all the node CAs of the cluster.


### 3. bootstrapping key on per node vTPM/TPM per cluster with a central CA

In this case, there is a central CA, instead of a CA per cluster (i.e. less CAs than the original setup in (1)). In this case, a RSA key pair will be generated per node, but will not be used as a CA. Instead, an external CA is used, which will perform a secure signing process with the vTPM/TPMs.

The RSA key pairs will be used to generate a certificate that endorses the key pair that is generated by the vTPM/TPMs, and the claims that the node/cluster is required to have (as described in "Binding trust with CA to key server"). 

The trust model is stronger since the operator no longer needs to be trusted, and that trust is now cetralized with the certificate authority.

In the step of "Binding trust with CA to key server", the trusted operator of the CA would perform the process only once with the centralized CA. Therefore, whenever new nodes/clusters are added, there is no need to perform this step again.


TODO: Add diagrams from PPT