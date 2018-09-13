# Trusted Identity - Key Release

This helm chart requires Helm v2.10.0 or higher. To upgrade your existing
helm, install/upgrade your client first.

E.g on Mac:

```console
brew install kubernetes-helm
# or
brew upgrade kubernetes-helm
# then upgrade your server:  
helm init --upgrade
```

## Setup the environment and deploy the Synthetic Load
This `synthetic-load` chart can be deployed in any Kubernetes environment including
IBM Container Cloud. Refer to [IBM Cloud documentation](https://console.bluemix.net/docs/containers/cs_tutorials.html#cs_tutorials)
if you have additional setup questions. Here are the typical steps for setting up
the deployment in IBM Container Cloud:

1.  Log in to the IBM Cloud CLI client. If you have a federated account, use `--sso`.
    ```console
    $ bx login [--sso]
    ```

1.  Get your IBM Cloud account ORG name that you want to use.
    ```console
    $ bx account orgs
    ```

1. Target the specific ORG
    ```console
    $ bx target -o <ORG_NAME>
    ```

1.  Get the ID of the cluster that you want to install `synthetic-load` in.
    ```console
    $ bx cs clusters
    ```

1. Setup the KUBECONFIG for selected cluster
    ```console
    $ bx cs cluster-config <CLUSTER_NAME>
    ```

1. Export the KUBECONFIG as per message obtained above
     ```console
     $ export KUBECONFIG=~/.bluemix/plugins/container-service/clusters/<CLUSTER_NAME>/<CLUSTER_CONFIG_FILE>
     ```

1. Test the kubectl access to your cluster
    ```console
    $ kubectl get nodes
    ```

1.  If you haven’t already, add the repo for this chart as given in the instructions [IBM Console Helm Charts Page](#https://console.bluemix.net/containers-kubernetes/solutions/helm-charts).

1.  [Target your Kubernetes CLI](https://console.bluemix.net/docs/containers/cs_cli_install.html#cs_cli_configure) to your cluster.

1.  Install the [Helm CLI](https://docs.helm.sh/using_helm/#installing-helm) and configure Helm in your cluster using the `helm init` command. IMPORTANT: be sure to follow the best practices on securing the installation.

1. Decide on parameters for the deployment:
* namespace - name of the namespace to deploy the workloads
* webService.podCount - number of pods in the deployment that is load balancing the `web-ms-service`
* webDeplGroup.podCount - number of pods in each group. There are always 10 groups deployed.

1. Deploy the `synthetic-load` chart, where webService.port value must be unique:

    ```console
    helm install --name=synthetic-load --namespace=default --set webService.port=30001 \
    --set webService.podCount=5 --set webDeplGroup.podCount=3 <helm-repo-name>/synthetic-load
    ```

1.  If you like to create a new values files instead of passing the values directly, use the example embedded in the chart.
    ```
    helm inspect values <helm-repo-name>/synthetic-load > config.yaml
    ```
    Where `<helm-repo-name>` is the name of the repository containing `synthetic-load` (added above or from `helm repo list`).

1.  Edit the values file with based on your needs.

1.  Deploy the `synthetic-load` into your cluster.
    ```console
    $ helm upgrade -i --values=config.yaml synthetic-load <helm-repo-name>/synthetic-load
    ```
