# Application Example using Universal Workload Identity with Tornjak and SPIRE (with Sidecar)

## Demo Overview
This example demonstrates a simple application that is using
Universal Workload Identity with Tornjak and SPIRE
to manage credentials stored securely in Vault.
There are two, independent web applications:
* [python](https://www.python.org/) (py)
* [Node.js](https://nodejs.org/en/) (node)

that connect to [MySQL](https://www.mysql.com/) database that stores
sample data records.

Access to this DB instance is never provided to the sample applications during
the application deployment, but instead,
it is dynamically obtained from the secure Vault by the `sidecar`, based on
the application (workload) identity verified by OIDC.

This document describes the following steps:
  - [Demo Overview](#demo-overview)
  - [Starting the database](#starting-the-database)
    - [*Info*: MySQL server](#info-mysql-server)
  - [Building the Demo application](#building-the-demo-application)
  - [Setting up Tornjak/SPIRE environment](#setting-up-tornjakspire-environment)
  - [Setting up Vault instance with OIDC enablement](#setting-up-vault-instance-with-oidc-enablement)
  - [Pushing the DB credentials to Vault](#pushing-the-db-credentials-to-vault)
  - [Configuring and deploying the sample application](#configuring-and-deploying-the-sample-application)
  - [Validating the application](#validating-the-application)
  - [Application management](#application-management)
  - [Updating/Changing credentials](#updatingchanging-credentials)
  - [Cleanup](#cleanup)

## Starting the database
Application will access the data from the database,
so first we need to deploy the MySQL database for storing the entries used by `py` and `node` applications.
The sample [deployment file](./config/db-node.yaml)
starts the DB container, Service for accessing it,
and populates it with a sample data.

### *Info*: MySQL server
MySQL server has a `root` user (admin) for which a password must be defined by providing a value for parameter `MYSQL_ROOT_PASSWORD`, and a technical user that application should use, we have named it `testroot` (value for parameter `MYSQL_USER`) and a password for our technical user by providing a value for parameter `MYSQL_PASSWORD`.
```yaml
  ...
  env:
    - name: MYSQL_PASSWORD
      value: testnewroot
    - name: MYSQL_ROOT_PASSWORD
      value: testroot
    - name: MYSQL_USER
      value: newroot
  ...
```

Deploy DB service:
```console
kubectl apply -f config/db-node.yaml
```


## Building the Demo application
This step is optional. You don't need to build your own images.
Instead, you can use the images publically available, stored in Docker Hub
[tsidentity](https://hub.docker.com/orgs/tsidentity) organization.

To build your own images,
You can change it to your own image repositity in [Makefile](./Makefile)

To build and push the images to the repository:
```console
make all
```

You can also build individual components e.g.
```console
make bin/python
make container-python
```

## Setting up Tornjak/SPIRE environment
This demo example can be running on any Kubernetes platform (Kind, Minikube, OpenShift,
IBM Cloud, AWS EKS, Azure etc.)

Install the Tornjak/SPIRE environment with OIDC Discovery for your platform,
as specified in [our tutorial](https://github.com/IBM/trusted-service-identity/blob/main/docs/spire-oidc-tutorial.md)

## Setting up Vault instance with OIDC enablement
Setup Tornjak with OIDC and Vault instance, by following the [tutorial](https://github.com/IBM/trusted-service-identity/blob/main/docs/spire-oidc-vault.md).

Create a vault instance per instructions [here](https://github.com/IBM/trusted-service-identity/blob/main/README.md#setup-vault).

Once Vault instance is up, setup the following environment variables:
* OIDC_URL
* ROOT_TOKEN
* VAULT_ADDR

Then run the [config/vault-oidc.sh](config/vault-oidc.sh) script.
This script will setup the permissions for accessing the secrets.
To change the policy role requirements, update the `sub` in `bound_claims`:

```json
"bound_claims": {
    "sub":"spiffe://openshift.space-x.com/region/*/cluster_name/*/ns/*/sa/*/pod_name/apps-*"
},
```

For example to restrict the access to US regions, and *my-app-sa* `ServiceAccount`
you can do a following:

```json
"bound_claims": {
    "sub":"spiffe://openshift.space-x.com/region/us-*/cluster_name/*/ns/*/sa/my-app-sa/pod_name/apps-*"
},
```

## Pushing the DB credentials to Vault
Now we can push our secret files to Vault. For this example we will be using two
files:
* config.json
* config.ini

Where the userid and password must match the DB values used in our
sample configuration [config/db-node.yaml](config/db-node.yaml)

where, for example, we can have [config/config.json](config/config.json):
```json
{
    "host"     : "db",
    "port"     : "3306",
    "user"     : "root",
    "password" : "testroot",
    "database" : "testdb",
    "multipleStatements": true,
    "debug": false
}
```
Insert it into Vault as keys:

```console
vault kv put secret/db-config/config.json @config.json
# retrieve it to test: 
vault kv get -format=json secret/db-config/config.json
```

The second file needed is [config/config.ini](config/config.ini):
```
[mysql]
host=db
port=3306
db=testdb
user=root
passwd=testroot
```

Since this file is not in JSON format, we can use a trick to encode it and
store its encoded value as a key:

```console
SHA64=$(openssl base64 -in config.ini )
vault kv put secret/db-config/config.ini sha="$SHA64"
# then to retrieve it:
vault kv get -field=sha secret/db-config/config.ini | openssl base64 -d
```

## Configuring and deploying the sample application
The applications will access the MySQL database and retrieve
the data stored there. The credentials for accessing this db
are stored in Vault, therefore
we have to update the Vault info in the deployment file
[config/apps.yaml](./config/apps.yaml)
and provide the value for *VAULT_ADDR* environment variable
to correspond to the VAULT_ADDR used earlier.

In order to retrieve the secrets we have created a set of scripts (bash, python).

For the `bash` variant of the script [sidecar/run-sidecar-alt.sh](./sidecar/run-sidecar-alt.sh) you can add the following code to your `yaml` file, in the *spec &#8594; template &#8594; spec &#8594; initContainers &#8594; command* :
```yaml
spec:
  ...
  template:
  ...
    spec:
      initContainers:
        - name: sidecar
        command: ["/usr/local/bin/run-sidecar-alt.sh", "/path/to/inputfile"]
        ...
```

Alternatively you can use the `python` variant of the script [sidecar/sidecar-script-alt.py](./sidecar/sidecar-script-alt.py) you can add the following code to your `yaml` file, in the *spec &#8594; template &#8594; spec &#8594; initContainers &#8594; command* :
```yaml
spec:
  ...
  template:
  ...
    spec:
      initContainers:
        - name: sidecar
        command: ["python3", "/usr/local/bin/sidecar-script-alt.py", "/path/to/inputfile"]
        ...
```

These scripts takes in a file as input, parses and stores each line into an array so that it knows which file to obtain from Vault and to put them in the specified volume mount.

In order to create an input file in a dynamic way we can use the help of the *ConfigMap* funtionality offered to us.

An example of a *ConfigMap* that would help us with the `inputfile` could look like:
```yaml
--- # seprator to a new section or "new file"
apiVersion: v1
kind: ConfigMap
metadata:
  name: path-to-inputfile #name of the configmap that would be used in the volume mount
data:
  inputfile.txt: | # each file we want to obtain from vault, each file on a new line
    db-config/config.ini
    db-config/config.json
```

This  would have to be defined in the `yaml` file in the *volumes* section, ie:
```yaml
...
spec:
  ...
  template:
  ...
    spec:
      volumes:
        - name: mount-inputfile
          configMap:
            name: path-to-inputfile
...
```

In order for the `"/path/to/inputfile"` to exists we would need to add also:
```yaml
...
spec:
  ...
  template:
  ...
    spec:
      initContainers:
        - name: sidecar
        ...
          volumeMounts:
            - name: mount-inputfile #name of the previous declared volume
              mountPath: /path/to/inputfile # no extension was used here, you can have inputfile.txt
              subPath: inputfile # no extension was used here, you can have inputfile.txt
```

A full example can be found here [config/apps.yaml](./config/apps.yaml).


Start the deployment:

```console
kubectl -n default create -f config/apps.yaml
```

When deployed, the `sidecar` *containerInit* would run first, obtain the JWT token with
SPIFFE ID and pass it to Vault with a request to get the secure files.
Once the files are received, they are mounted to common directory available to
other containers in the pod, and the `sidecar` container exits.

Then, `node` and `py` start, and they can use these securely stored and transmitted files.

To deploy individual applications (*without the sidecars*):

Deploy Node App service:

```console
kubectl apply -f config/app-node.yaml
```

Deploy Python App service:

```console
kubectl apply -f config/app-python.yaml
```

## Validating the application
Now we need to access the applications. This process depends on the underlining
platform. Here we provide examples for Minikube, Kind, and OpenShift in IBM Cloud.
Check with your service provider how to access the running containers via services.

<details><summary>Click to view Minikube steps</summary>

[**TODO:** *These need to be checked/updated*]

Execute the following command to get the URL of the Node App:
```console
minikube service app-node -n default --url
```
We should see:
```
🏃  Starting tunnel for service app-node.
|-----------|----------|-------------|------------------------|
| NAMESPACE |   NAME   | TARGET PORT |          URL           |
|-----------|----------|-------------|------------------------|
| default   | app-node |             | http://127.0.0.1:59980 |
|-----------|----------|-------------|------------------------|
http://127.0.0.1:59980
❗  Because you are using a Docker driver on darwin, the terminal needs to be open to run it.
```
---

Execute the following command to get the URL of the Python App:
```console
minikube service app-py -n default --url
```
We should see:
```
🏃  Starting tunnel for service app-py.
|-----------|--------|-------------|------------------------|
| NAMESPACE |  NAME  | TARGET PORT |          URL           |
|-----------|--------|-------------|------------------------|
| default   | app-py |             | http://127.0.0.1:60042 |
|-----------|--------|-------------|------------------------|
http://127.0.0.1:60042
❗  Because you are using a Docker driver on darwin, the terminal needs to be open to run it.
```
</details>

<details><summary>Click to view Kind steps</summary>

[**TODO:** *These need to be checked/updated*]

On kind, we can use port-forwarding to get HTTP access to applications:

kubectl -n default port-forward spire-server-0 10000:10000

Forwarding from 127.0.0.1:10000 -> 10000
Forwarding from [::1]:10000 -> 10000

Now you can test the connection to Tornjak server by going to http://127.0.0.1:10000 in your local browser.
</details>

<details><summary>Click to view OpenShift steps</summary>

First obtain the ingress name using *ibmcloud* cli:

```console
$ # first obtain the cluster name:
$ ibmcloud ks clusters
$ # then use the cluster name to get the Ingress info:
$ ibmcloud ks cluster get --cluster <cluster_name> | grep Ingress
Ingress Subdomain:              space-x04-9d995xxx4-0000.eu-de.containers.appdomain.cloud
Ingress Secret:                 space-x04-9d995xxx4-0000
Ingress Status:                 healthy
Ingress Message:                All Ingress components are healthy
```
Build an ingress file, using the Ingress Subdomain information obtained above.
Use any arbitrary prefix to distinguish the applications.
For example for host: `space-x04-9d995xxx4-0000.eu-de.containers.appdomain.cloud`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: apps-ingress
  namespace: default
spec:
  rules:
  - host: py.space-x04-9d995xxx4-0000.eu-de.containers.appdomain.cloud
    http:
      paths:
      - pathType: Prefix
        path: "/"
        backend:
          service:
            name: apps
            port:
              number: 8000
  - host: node.space-x04-9d995xxx4-0000.eu-de.containers.appdomain.cloud
    http:
      paths:
      - pathType: Prefix
        path: "/"
        backend:
          service:
            name: apps
            port:
              number: 8001
```

Then access the service using the provided host values:
* http://py.space-x04-9d995xxx4-0000.eu-de.containers.appdomain.cloud
* http://node.space-x04-9d995xxx4-0000.eu-de.containers.appdomain.cloud

</details>

## Application management

[**TODO:** *describe how to operate (add/remove) entries into DB. *]

## Updating/Changing credentials

[**TODO:** *describe how to update the credentials for accessing DB *]

## Cleanup
Remove the deployments:

```console
kubectl -n default delete ConfigMap path-to-inputfile
kubectl -n default delete -f config/apps.yaml
kubectl delete -f config/db-node.yaml
```

Remove minikube instance:

```console
minikube delete
```
