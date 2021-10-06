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