```
minikube start --kubernetes-version=v1.20.2

export CLUSTER_NAME=minikube
export SPIRESERVER_NS=tornjak
kubectl create ns $SPIRESERVER_NS
helm install --set "namespace=tornjak" --set "clustername=$CLUSTER_NAME" --set "trustdomain=openshift.space-x.com" tornjak charts/tornjak --debug
minikube service spire-server -n $SPIRESERVER_NS --url

export SPIRE_SERVER=127.0.0.1
export SPIRE_PORT=52677

minikube service tornjak-http -n $SPIRESERVER_NS --url

<!-- kubectl -n $SPIRESERVER_NS port-forward spire-server-0 10000:10000 -->

export AGENT_NS=spire
kubectl create namespace $AGENT_NS

kubectl get configmap spire-bundle -n "$SPIRESERVER_NS" -o yaml | sed "s/namespace: $SPIRESERVER_NS/namespace: $AGENT_NS/" | kubectl apply -n "$AGENT_NS" -f -

kubectl -n spire apply -f spire-bundle.yaml

kubectl -n $AGENT_NS create -f- <<EOF
kind: Service
apiVersion: v1
metadata:
  name: spire-server
spec:
  type: ExternalName
  externalName: spire-server.tornjak.svc.cluster.local
  ports:
  - port: 8081
EOF

export SPIRE_SERVER=spire-server.tornjak.svc.cluster.local
export SPIRE_PORT=8081

helm install --set "spireServer.address=$SPIRE_SERVER" \
--set "spireServer.port=$SPIRE_PORT"  --set "namespace=$AGENT_NS" \
--set "clustername=$CLUSTER_NAME" --set "region=us-east" \
--set "trustdomain=openshift.space-x.com" \
spire charts/spire --debug
```

Config Local Vault
```192.168.59.100
mkdir vault

tee -a vault/config.hcl <<EOF
listener "tcp" {
   address     = "127.0.0.1:8200",
   tls_disable = 1
}

storage "file" {
   path = "vault-storage"
}
EOF
```

Follow [Vault documentation](https://spiffe.io/docs/latest/keyless/vault/readme/#create-the-config-file-and-run-the-vault-server) to unseal and setup secrets.

```console
vault kv put secret/db-config/config.json @config.json
# retrieve it to test: 
vault kv get -format=json secret/db-config/config.json
```

```console
SHA64=$(openssl base64 -in config.ini )
vault kv put secret/db-config/config.ini sha="$SHA64"
# then to retrieve it:
vault kv get -field=sha secret/db-config/config.ini | openssl base64 -d
```

Create vault
```
kubectl create ns tsi-vault
kubectl -n tsi-vault create -f trusted-service-identity/examples/vault/vault.yaml
minikube service tsi-vault -n tsi-vault --url
```

# Register workload Registrar
https://github.com/IBM/trusted-service-identity/blob/docs/docs/spire-workload-registrar.md#register-workload-registrar-with-the-spire-server


/opt/spire/bin/spire-server entry create -admin \
-selector k8s:ns:spire \
-selector k8s:sa:spire-k8s-registrar \
-selector k8s:container-name:k8s-workload-registrar \
-spiffeID spiffe://openshift.space-x.com/mycluster/workload-registrar1 \
-parentID spiffe://openshift.space-x.com/spire/agent/k8s_psat/agent_spiffe_id \
-registrationUDSPath /run/spire/sockets/registration.sock


/opt/spire/bin/spire-server entry show \
-registrationUDSPath /run/spire/sockets/registration.sock

helm install --set "spireServer.address=$SPIRE_SERVER" \
--set "spireServer.port=$SPIRE_PORT"  --set "namespace=$AGENT_NS" \
--set "clustername=$CLUSTER_NAME" --set "region=us-east" \
--set "trustdomain=openshift.space-x.com" \
spire charts/spire --debug
