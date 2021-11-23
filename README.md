# Tornjak.io Examples

Start minikube
```
minikube start --kubernetes-version=v1.20.2
```

Deploy DB service
```
kubectl apply -f db-node.yaml
```
Deploy Node App service
```
kubectl apply -f app-node.yaml
```
Deploy Pyton App service
```
kubectl apply -f app-python.yaml
```

---

Execute the following command to get the URL of the Node App:
```
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
```
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

---
Remove minikube instance
```
minikube delete
```

---

To build and push images to the repository:
```console
make all
```
---
Enable the Sidecar

after executing `make all`,

* install Vault as specified [here](https://github.com/IBM/trusted-service-identity/blob/main/README.md#setup-vault)
* run Vault configuration using [config/vault-oidc.sh] script
* insert db configuration into Vault

```console
export ROOT_TOKEN=
export VAULT_ADDR=http://tsi-vault-tsi-vault.space-x04-9d995c4a8c7c5f281ce13d5467ff6a94-0000.eu-de.containers.appdomain.cloud

vault kv put secret/db-config.json @../nodejs/config.json
```

Run the sidecar (first by itself)

```console
kubectl create ns mission
kubectl -n mission create -f config/sidecar.yaml
```

Get inside
```console
kubectl -n mission get po
kubectl -n mission exec -it <uuid> -- bash
```

Run the script manually:
```console
root@kube-c20o1lbd0mhbu12dbd0g-tsikube01-default-00000170:/# /usr/local/bin/run-sidecar.sh
root@kube-c20o1lbd0mhbu12dbd0g-tsikube01-default-00000170:/# cat /run/db/config.json
{
  "database": "testdb",
  "debug": false,
  "host": "db",
  "multipleStatements": true,
  "password": "testroot",
  "port": "3306",
  "user": "root"
}
```

I can't start the `apps.yaml`. I get this error:

```
examples-tornjak$k -n mission logs apps-668f7f559d-wbspx -c node
node:events:368
      throw er; // Unhandled 'error' event
      ^

Error: getaddrinfo ENOTFOUND db
    at GetAddrInfoReqWrap.onlookup [as oncomplete] (node:dns:71:26)
    --------------------
    at Protocol._enqueue (/usr/src/app/node_modules/mysql/lib/protocol/Protocol.js:144:48)
Running on http://0.0.0.0:8080
    at Protocol.handshake (/usr/src/app/node_modules/mysql/lib/protocol/Protocol.js:51:23)
    at Connection.connect (/usr/src/app/node_modules/mysql/lib/Connection.js:116:18)
```


## Vault Setup
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

For example to restrict the access to US regions, and *my-app* `ServiceAccount`
you can do a following:

```json
"bound_claims": {
    "sub":"spiffe://openshift.space-x.com/region/us-*/cluster_name/*/ns/*/sa/my-app/pod_name/apps-*"
},
```

Now we can push our secret files to Vault. For this example we will be using two
files:
* config.json
* config.ini

where for example, we can have *config.json*:
```json
{
    "host"     : "db",
    "port"     : "3306",
    "user"     : "root",
    "password" : "password",
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

The second file is *config.ini*:
```
[mysql]
host=db
port=3306
db=testdb
user=root
passwd=password
```

Since this file is not in JSON format, we can use a trick to encode it and
store its value a key:

```console
SHA64=$(openssl base64 -in config.ini )
vault kv put secret/data/db-config/config.ini sha="$SHA64"
# then to retrieve it:
vault kv get -field=sha secret/db-config/config.ini | openssl base64 -d
```

## Start an application
Before we run an application, we have to provide the Vault in the deployment file
[config/apps.yaml](config/apps.yaml) and update the value for *VAULT_ADDR* environment
variable to correspond with the VAULT_ADDR used above.

Start the deployment:

```console
kubectl -n default create -f config/apps.yaml
```

When deployed, the `sidecar` *containerInit* would run first, obtain the JWT token with
SPIFFE ID and pass it to Vault with a request to get the secure files.
Once the files are received, they are mounted to common directory available to
other containers in the pod, and the `sidecar`container exits.

Then, `node` and `py` start, and they can use these securely stored and transmitted files. 
