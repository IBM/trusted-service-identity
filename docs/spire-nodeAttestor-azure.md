# [** DRAFT ***] Setting up the SPIRE Azur NodeAttestor

## NOTICE:
The Azure nodeAttestor currently supports only the Azure cluster that has since of 1 node. See the issue https://github.com/spiffe/spire/issues/2527

## Create AKS (Azure Kubernetes Service)

## Setting up the cluster

https://docs.microsoft.com/en-us/azure/aks/kubernetes-walkthrough-portal

Login via Chrome to https://portal.azure.com/ with
@us.ibm.com account.

Install azure-cli on mac:

```console
brew install azure-cli

# login:
az login --use-device-code
```

Go to https://microsoft.com/devicelogin and
and enter the code xxxx to authenticate.

```console
az account set --subscription cea-xxx
az aks get-credentials --resource-group ms-resource-group --name azure-tornjak-02
```

Create a cluster:
```console
az aks create -g ms-resource-group -n azure-tornjak-02 --enable-managed-identity
# get KUBECONFIG:
az aks get-credentials --resource-group ms-resource-group --name azure-tornjak-02
```

Then scale down the nodepool to 1.
https://portal.azure.com/#@ibm.onmicrosoft.com/resource/subscriptions/cea7f60c-xxxx/resourceGroups/ms-resource-group/providers/Microsoft.ContainerService/managedClusters/azure-tornjak-02/nodePools

Get TENANT information
https://docs.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal
https://docs.microsoft.com/en-us/azure/active-directory/fundamentals/active-directory-how-to-find-tenant

```console
az account list
az account tenant list
```

Azure MSI:
https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/overview

https://docs.microsoft.com/en-us/azure/container-instances/container-instances-managed-identity?context=/azure/active-directory/managed-identities-azure-resources/context/msi-context

## Setting up the SPIRE Server configuration

```console
NodeAttestor "azure_msi" {
    enabled = true
    plugin_data {
        tenants = {
            // Tenant configured with the default resource id (i.e. the resource manager)
            "fcf67057-xxx-xxx" = {}
        }
    }
}
```

## Setting up the SPIRE agents
On Agents:
```console
helm install --set "spireServer.address=$SPIRE_SERVER" --set "clustername=azure-tornjak-01" \
--set "azure=true"  --set "region=us-east" --set "trustdomain=openshift.space-x.com" \
spire charts/spire --debug
```

Update the configMap `spire-agent`:

```json
 plugins {
      NodeAttestor "azure_msi" {
          plugin_data {
           }
       }
      KeyManager "memory" {
        plugin_data {
        }
      }
      WorkloadAttestor "k8s" {
        plugin_data {
         // kubelet_read_only_port = 10255
          skip_kubelet_verification = true
         }
      }
    }
```

Only first instance can be registered with the Spire server.

If fails, that's because other token already issued, delete the agent instance, and wait for the agent to restart.

Format:
```
spiffe://<trust domain>/spire/agent/azure_msi/<tenant_id>/<principal_id>
spiffe://openshift.space-x.com/spire/agent/azure_msi/fcf67057-5xxx/a4cdb7a6-xxx
```

Error for 1+ agents:
```
time="2021-09-11T17:17:29Z" level=error msg="Agent crashed" error="failed to get SVID: error getting attestation response from SPIRE server: rpc error: code = Internal desc = failed to attest: azure-msi: MSI token has already been used to attest an agent"
trusted
on Server:
time="2021-09-11T17:17:27Z" level=error msg="Failed to attest" caller-addr="172.30.118.52:57104" error="rpc error: code = Unknown desc = azure-msi: MSI token has already been used to attest an agent" method=AttestAgent node_attestor_type=azure_msi service=agent.v1.Agent subsystem_name=api
time="2021-09-11T17:17:29Z" level=error msg="Failed to attest" caller-addr="172.30.15.46:36746" error="rpc error: code = Unknown desc = azure-msi: MSI token has already been used to attest an agent" method=AttestAgent node_attestor_type=azure_msi service=agent.v1.Agent subsystem_name=api
time="2021-09-11T17:17:45Z" level=error msg="Failed to attest" caller-addr="172.30.15.46:37034" error="rpc error: code = Unknown desc = azure-msi: MSI token has already been used to attest an agent" method=AttestAgent node_attestor_type=azure_msi service=agent.v1.Agent subsystem_name=api
time="2021-09-11T17:18:15Z" level=error msg="Failed to attest" caller-addr="172.30.15.46:37386" error="rpc error: code = Unknown desc = azure-msi: MSI token has already been used to attest an agent" method=AttestAgent node_attestor_type=azure_msi service=agent.v1.Agent subsystem_name=api
```

spiffe://openshift.space-x.com/spire/agent/azure_msi/fcf67057-5xxx/a4cdb7a6-xxx

Obtain principal_id:

```console
az aks list
```

```json
"identityProfile": {
  "kubeletidentity": {
    "clientId": "63eb7ba1-1cbf-4267-b010-8b99b8945f58",
    "objectId": "a4cdb7a6-bc88-47fd-9e06-0e7710a17fc7",
    "resourceId": "/subscriptions/cea7f60c-xxx/resourcegroups/MC_ms-resource-group_azure-tornjak-02_eastus/providers/Microsoft.ManagedIdentity/userAssignedIdentities/azure-tornjak-02-agentpool"
  }
},
"kubernetesVersion": "1.20.9",
"linuxProfile": {
  "adminUsername": "azureuser",
  "ssh": {
    "publicKeys": [
      {
        "keyData": "ssh-rsa AAAAzzxxxx/jb\n"
      }
    ]
  }
},
"location": "eastus",
"maxAgentPools": 100,
"name": "azure-tornjak-02",
```

Get the identity list:
```
az identity list
```
Sample:
```json
[
  {
    "clientId": "63eb7ba1-1cbf-4267-b010-8b99b8945f58",
    "clientSecretUrl": "https://control-eastus.identity.azure.net/subscriptions/cea7f60c-0304-43ca-939d-83f3bc4f9883/resourcegroups/MC_ms-resource-group_azure-tornjak-02_eastus/providers/Microsoft.ManagedIdentity/userAssignedIdentities/azure-tornjak-02-agentpool/credentials?tid=fcf67057-xxxx&oid=a4cdb7a6-xxx&aid=63eb7ba1-xxxx",
    "id": "/subscriptions/cea7f60c-xxx/resourcegroups/MC_ms-resource-group_azure-tornjak-02_eastus/providers/Microsoft.ManagedIdentity/userAssignedIdentities/azure-tornjak-02-agentpool",
    "location": "eastus",
    "name": "azure-tornjak-02-agentpool",
    "principalId": "a4cdb7a6-xxx",
    "resourceGroup": "MC_ms-resource-group_azure-tornjak-02_eastus",
    "tags": {},
    "tenantId": "fcf67057-xxx",
    "type": "Microsoft.ManagedIdentity/userAssignedIdentities"
  }
]
```
