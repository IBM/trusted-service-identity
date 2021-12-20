# Attack surface reduction with TSI


## Introduction
Vault is a tool for securely accessing and storing secrets. A secret is anything that controls access to data or service, such as API keys, passwords, or certificates. Vault provides a unified interface to any secret while providing tight access control and recording a detailed audit log. 
For the purpose of this document, let's call the secrets stored in the Vault application secrets. These could be secrets that application uses to open connection to other services or retrieve the sensitive data from the database.
When an application (a workload) is hosted in Kubernetes cluster, before retrieving the application secrets from Vault, it first needs to authenticate itself with Vault. Let's call these secrets vault access secrets.
 
(Vault security model: https://www.vaultproject.io/docs/internals/security)

## Vault without TSI
To authenticate with Vault, an application must obtain the Vault authentication information, (vault access secrets) in runtime, because these secrets cannot be stored in the container image. This is typically done via  Kubernetes secret. The problem with the Kubernetes secrets is that once they are stored, they would be also available to administrators, cloud operators or anyone with access to this namespace. However, the admins might be third-party employees just managing the resources, might not be certified to access the data or might not have security clearance. This process of managing vault access secrets is manual and gives human operator access to Vault. The storage of where these vault access credentials reside have a larger attack surface - e.g.  API server level, etcd access.  Additionally, there is no easy way to retain an accurate audit trail, to track who accessed what secret and when.
 
Another problem is that vault access secrets are static and long lived. Static, because the same secret for accessing Vault would be given to all instances of the application and that makes the audit much harder. Since the vault access secrets are long lived, there is a higher risk of exposure for a rogue credential usage.  

In addition, the traditional binding of certificates to IP addresses via TLS to ensure that the client is who they claim is not effective in container based deployments as IP addresses are not fixed. Therefore, there is a gap in validating the delivery of secrets to the correct container. If a cert is stolen it can be used from a different location.

## List of security issues and corresponding threats:
(This is a list of security issues associated with the use of Kubernetes secrets and the direct threats. The table below shows how various technologies address them (or not)):

* **VSI01** - Application secrets and keys are static – the same values for all deployment members
  - **Threat**: Blast radius is wide, no accountability of lost secrets; unnecessary risk and widening the risk profile
* **VSI02** - Application secrets are managed by the cluster operator instead of the secret owner (including access control, audit logging, encryption at rest etc.)
  - **Threat**: Lack of separation of duties and principle of least privilege w.r.t. secret management (i.e. Application secrets managed by the cluster operator instead of the secret owner)
* **VSI03** - Cluster operator has direct access to application secrets/keys 
  - **Threat**: Cluster operator can use the secrets to read the sensitive data
* **VSI04** - Cluster operator has access to vault authentication information 
  - **Threat**: Cluster operator can access to the vault authentication information, then read the vault secrets authorized to this account and use them to access the sensitive data  
* **VSI05** - Vault authentication information is static and long-lived, 
  - **Threat**: Blast radius for Vault authentication is wide. Unnecessary risk  
* **VSI06** - Vault authorization is not fine-grained, single credential - multiple use / difficult to manage
  - **Threat**: CapitalOne Problem - identity of a single VM has access to several components 
* **VSI07** - Lack of “lockdown” capabilities at the cluster level and easy compliance policy enforcement (through undertaking parts of secret delivery and management)
  - **Threat**: Lack of compliance enforcement mechanism (e.g. "lockdown") 
* **VSI08** - Lack of location-based restriction enforcement, preventing the geo-facing. 
  - **Threat**: Malicious user can access data from unauthorized location or spoof the location identity 
* **VSI09** - Lack of process for secure delivery of secret to correct application
  - **Threat**: Unauthorized applications can access the sensitive data
* **VSI10** - System is exposed to significant manual work by humans, thus prone to errors and less secure
  - **Threat**: Humans make mistakes and compromise sensitive information 
* **VSI11** - No easy process for key rotation or key revocation. Secrets need to be modified directly
  - **Threat**: Key rotation is not enforced and not secure, manual work
* **VSI12** - Trust of secrets are tied to k8s  apiserver, with lower security guarantees (i.e. k8s vs host, TPM);
  - **Threat**: K8s secrets are not secure with a wide exposure plane
* **VSI13** - Lack of hardware root of trust bootstrapping 
  - **Threat**: Cloud provider is able to violate software/process-based chain of trust and modify the certificates and private keys
* **VSI14** - Container memory is visible to the host kernel  
  - **Threat**: Highly privileged cloud provider is able to affect confidentiality and integrity of in-use credentials in orchestration 

Table Legend:
* X - Not available
* &#10003; - Resolved/Mitigated
* [#] - Refer to footnote

| imp \ VSI            | 01        | 02       | 03       | 04       | 05       | 06       | 07       | 08            | 09       | 10       | 11       | 12       | 13       | 14       |
|----------------------|-----------|----------|----------|----------|----------|----------|----------|---------------|----------|----------|----------|----------|----------|----------|
| Vault                |  &#10003; | &#10003; | &#10003; | x        | x        | x        | x        | x             | x        | x        | x        | x        | x        | x        |
| Vault +TSI           | &#10003;  | &#10003; | &#10003; | &#10003; | &#10003; | &#10003; | &#10003; |  &#10003; [1] | &#10003; [2]| &#10003; [3] | &#10003; [4] | &#10003; [5]| x        | x        |
| Vault +TSI +TPM      | &#10003;  | &#10003; | &#10003; | &#10003; | &#10003; | &#10003; | &#10003; | &#10003; [1]  | &#10003; [2]| &#10003; [3]| &#10003; [4] | &#10003; [5] | &#10003; [6]| x        |
| Vault +TSI +TPM +TEE | &#10003;  | &#10003; | &#10003; | &#10003; | &#10003; | &#10003; | &#10003; | &#10003; [1]  | &#10003; [2]| &#10003; [3]| &#10003; [4]| &#10003; [5]| &#10003; [6]| &#10003; [7]|

- TPM - Trusted Platform Module
- TEE – Trusted Execution Environment    

Footnotes:
* **VSI08**: [1] TSI ensures location trust boundary enforcement through embedding the location properties into the certificate structure
* **VSI09**: [2] Future work for TSI to do this based on label/context based routing validation of certificate to perform secure delivery of secrets
* **VSI10**: [3] Is reduced to remove all operator specific interactions. Only limiting to a initial setup with a person of high privilege, i.e. CISO
* **VSI11**: [4] TSI makes it easier for application to manage secrets and ensure the security of them by handling rotations, revocations, etc. However, once the handoff of secret data for use is done to the application, the application is still responsible for the secret data.
* **VSI12**: [5] *+TSI* - BEFORE, secrets are tied to the security of the k8s apiserver and its operators. AFTER, the security of a node and the trust of which it is bootstrapped with. I.e. The assurance of the secret is tied to the integrity and confidentiality of the node.
* **VSI13**: [6] *+TSI+TPM* - Ties the confidentiality and integrity of a secret to the integrity and confidentiality to the of the TPM and TSI signing components. In this case, minting of identities cannot leave the node, and integrity of secrets are but the identities minted can be observed. 
* **VSI14**: [7] *+TSI+TPM+TEE* - Signing and measurement services and the TPM are protected fully in this case, The security of the identity is tightly coupled with the TPM and environment in which it is run with, based on the security of the underlying hypervisor.


## Vault with TSI 
Vault with TSI as a stand-alone deployment mitigates the following issues:
- Operator has no access to vault authentication information (VSI04)
- Vault authentication information is no longer static or long-lived (VSI05)
- Vault authorization is fine-grained, different credentials for same deployments, easier to manage (VSI06)
- Provides the `lockdown` capabilities and easy compliance policy enforcement (VSI07)
- Location based restriction enforcement (VSI08) 
- Securely delivers secrets to correct application (Future work for TSI to do this based on label/context based routing validation of certificate to perform secure delivery of secrets) (VSI09)
- Amount of manual human exposure (VSI10): Is reduced to remove all operator specific interactions. Only limiting to a initial setup with a person of high privilege, i.e. CISO
- Need to modify application to reduce risk and attack surface of secrets (VSI11): TSI makes it easier for application to manage secrets and ensure the security of them by handling rotations, revocations, etc. However, once the handoff of secret data for use is done to the application, the application is still responsible for the secret data.
- How to tie security of secrets to certain security level (VSI12): BEFORE, secrets are tied to the security of the k8s apiserver and its operators. AFTER, the security of a node and the trust of which it is bootstrapped with. I.e. The assurance of the secret is tied to the integrity and confidentiality of the node.

Trusted Service Identity protects sensitive data access by ensuring only attested services are able to obtain credentials. This is done through the use of workload identity, composed of various run-time measurements like the image and cluster name, data center location, etc, to identify the application. These measurements are securely signed by a service running on every hosting node, using a chain of trust installed during the secure bootstrapping of the environment. And since there are no secrets stored in the K8s cluster, TSI solution is significantly reducing the attack vector. 
Some highly regulated industries require more fine-grained controls like to be able to express, enforce and audit data access via location (or other properties) of the workloads, i.e. GDPR. Trusted Service Identity provides just that. By exposing the properties of workloads in the definition of policies governing secrets, it provides the ability to create policies such as "*Only workload X (with this image), running in datacenter DAL05, in kube cluster hipaaCluster can access medical records in this Cloudant database*". This method of governance has very fine-grained controls, that might apply to a wide spectrum of use-cases. In addition, the entire audit trail is retained, tracking every interaction and what process received what secret and when. 
TSI also allows using different data for various deployment types (development, staging and production). 




## Vault with TSI and TPM
The model so far relies on no access to the underlying host - i.e trusting the main functions of container isolation and kubernetes access enforcement to worker nodes and workloads OR someone having access to the baremetal host in the datacenter. The use of a TPM (Trusted Platform Module) limits the scope of integrity and confidentiality attacks that can be done on the TSI process. Since all the private keys and intermediate CAs used for signing the JWT Tokens are protected by hardware TPM and they are not accessible to the theft  even when the JSS component is compromised. They cannot be stolen and move to another location. TPM provides a tamper proof, hardware based chain of trust, as it ensures that the minting of tokens need to go through the system and will be audited, thereby providing assurance of blast radius in the event of an attack.

In addition, Vault with TSI with TPM mitigates the following issues:
- It ties security of secrets to certain security level (VSI12): Ties the confidentiality and integrity of a secret to the integrity and confidentiality to the of the TPM and TSI signing components. In this case, minting of identities cannot leave the node, and integrity of secrets are but the identities minted can be observed. 


## Vault with TSI, TPM and Trusted Execution Environment (secure encrypted VM)

In this scenario, we assume that the setup is that TSI components are run within secure encrypted VMs with a secure channel to talk to the TPM, and an ability to observe the container orchestration system for measurement in a secure manner (like a secure microkernel design). This will help protect the logic and process flows of the critical aspects of TSI to further secure the confidence in the identity provided by the system.

In addition, TSI with TPM with secure encrypted VMs mitigates the following issues: 
- It ties security of secrets to certain security level (VSI12): Signing and measurement services and the TPM are protected fully in this case, The security of the identity is tightly coupled with the TPM and environment in which it is run with, based on the security of the underlying hypervisor.

## Vault with Vault Agent Sidecar
There are several similarities with TSI. Vault Agent uses annotations with go templates formatters to define what secrets need to be retrieved from Vault and how to present them back to the application. Mutating Admission Webhook injects `init` and/or `sidecar` to the deployment. `Init` retrieves the secret before the application starts, then `sidecar` refreshes the secret continuously. Vault Policy is tied to K8s Service Accounts. 
Vault Sidecar vs TSI:
For Vault Sidecar to work, the Kubernetes elements need to be trusted (APIs, kube, etcd). Heavy reliance on service accounts 
Application consuming the secret experiences a similar behavior as with TSI, but in contrast, in TSI the decision about whether the secret is released to the application is made externally to the K8s cluster, thus provides better audit tracking capabilities and decouples the runtime environment from decision making. 
Using a multi-cluster solution with Vault Agent would require recreating the policies as they cannot be easily migrated from one cluster to another


### TSI can enable additional security measures (future work)

## TSI with Encrypted Containers 

Encrypted Container Images protects the confidentiality of the workload/code by extending the OCI (Open Container Initiative) container image specification with +encrypted media types, which allows developers to encrypt container images, so that they can only be decrypted by authorized parties (developers, clusters, machines, etc.). This ensures that the workload stays encrypted from build to run-time. Without the appropriate key, even in the event of the registry compromise, the content of the image remains confidential. 
But how do we ensure that this workload is only run in particular clusters or regions? How do we enforce export control or digital rights management? These are natural uses of Encrypted Container Images. By only providing the appropriate decryption keys through attestation, authorization and key management, we can create a trust binding between certain clusters/workers and workloads. This will provide assurance of knowing WHERE workloads are running.
