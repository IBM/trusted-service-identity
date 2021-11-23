# Tornjak.io Examples

Start minikube
```
minikube start --kubernetes-version=v1.20.2
```

Deploy DB service
```
kubectl apply -f config/db-node.yaml
```
Deploy Node App service
```
kubectl apply -f config/app-node.yaml
```
Deploy Pyton App service
```
kubectl apply -f config/app-python.yaml
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
