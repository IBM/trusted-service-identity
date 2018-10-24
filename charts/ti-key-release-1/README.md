# Trusted Identity - Key Release
This is a first chart (out of 2) to execute a deployment of the Trusted Identity
for managing keys for Key Store and JWT Tokens.

## Prerequisites
This helm chart requires Helm v2.10.0 or higher. To upgrade your existing
helm server, install (or upgrade) your client first.

E.g on Mac:

```console
brew install kubernetes-helm
# or
brew upgrade kubernetes-helm
# then upgrade your server:  
helm init --upgrade
```

## Setup the environment and deploy the Trusted Identity
This `ti-key-release-1` chart can be deployed in any Kubernetes environment including
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

## Create and setup a Namespace for Trusted Identity
This chart requires the namespace to be created manually before executing the chart
deployment:

```console
kubectl create namespace trusted-identity
```

Once the `trusted-identity` namespace created, populate the required secrets.
Currently the images for Trusted Identity project are stored in Artifactory. In order to
use them, user has to be authenticated. You must obtain the [API key](https://pages.github.ibm.com/TAAS/tools_guide/artifactory/authentication/#authenticating-using-an-api-key)
as described above.

Create a secret that contains your Artifactory user id (e.g. user@ibm.com) and API key.
(This needs to be done every-time the new namespace is created)

```console
kubectl -n trusted-identity create secret docker-registry regcred \ --docker-server=res-kompass-kompass-docker-local.artifactory.swg-devops.com
--docker-username=user@ibm.com \
--docker-password=${API_KEY} \
--docker-email=user@ibm.com

# to check your secret:
kubectl -n trusted-identity get secret regcred --output="jsonpath={.data.\.dockerconfigjson}" | base64 --decode
```

This chart uses several parameters defined in the values.yaml file:
```console
helm inspect values ti-key-release-1-0.1.0.tgz
```

* namespace - the namespace associated with this deployment. It must match the namespace created above
* vaultAddress - location of the Vault Server e.g. https://1.1.1.1:32222
* rootToken, rootCaCrt, rootCaKey and rootCaSrl - values specific to Root CA
* jwtkey - private key for JWT injection (see the chapter below about crating a new private key)


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

### Build this chart
To package this helm chart:
```console
cd TI-KeyRelease
helm package charts/ti-key-release-1
```

## Create your own private key and public JSON Web Key Set (JWKS)
Before enabling the JWT policy in Istio, you need to first create a private key
and JWKS. The following steps are based on [this doc](https://github.com/istio/istio/blob/release-1.0/security/tools/jwt/samples/README.md)
This can be done from inside the sidecar container:

```console
kubectl -n trusted-identity exec -it <my_ubuntu_pod_id> -c jwt-sidecar /bin/bash
# generate private key using openssl
openssl genrsa -out key.pem 2048
# run gen-jwt.py with --jkws to create new public key set (JWKS) and sample JWT
python gen-jwt.py key.pem -jwks=./jwks.json --expire=60 --claims=foo:bar > demo.jwt
```

Preserve the newly created `key.pem` and `jwks.json`. Put the public JWKS to publicly accessible place e.g.
https://raw.githubusercontent.com/mrsabath/jwks-test/master/jwks.json in public GITHUB: https://github.com/mrsabath/jwks-test/blob/master/jwks.json

Put the private key to [./charts/ti-key-release-2/values.yaml](./charts/ti-key-release-2/values.yaml)

```yaml

ti-key-release-1:
  jwtkey: |-
    -----BEGIN RSA PRIVATE KEY-----
    MIIEogIBAAKCAQEAtRcoFKRhV5+1w3r9ZrDeT4XKaREaher2dAfg0i82Te2QG1B5
    . . . .
         ***** MY KEY *****
    . . . .
    Au57AoGALTlcO/AMzyj/UjE+/6wP0nYuw90FitYq9h9q9jSYIMyxwQWJa4qWwkp9
    0vuUNDqsbzFeqqG55f0FZp3bfmNExNs0igdcTzwfqt6Q4LGkZVFYicbshIxHDC0a
    fn3/DuZcMg+chQ970y+XF5JtUwgVbYfaMiP1zrF0J6Fh4rHk3Cw=
    -----END RSA PRIVATE KEY-----
```
Then redeploy the charts and your container.
