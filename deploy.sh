#!/bin/bash
KEYS="charts/ti-key-release-1/keys/"

cd "$( dirname "${BASH_SOURCE[0]}")"

if [ ! -d "$KEYS" ]; then
    echo "ERROR: $KEYS directory doesn't exist"
    exit 1
  # Control will enter here if $DIRECTORY doesn't exist.
fi

./cleanup.sh

# check if the namespace was removed
while kubectl get ns trusted-identity | grep Terminating; do sleep 5;done
kubectl create namespace trusted-identity

# Check
kubectl -n trusted-identity create secret generic ti-keys-config --from-file=$KEYS

# Create rbac bindings
kubectl -n trusted-identity create -f deployment/tiRBAC.yaml
# Create configs and keys
kubectl -n trusted-identity apply -f deployment/crd/crd_clusterinfo.yaml
kubectl -n trusted-identity apply -f deployment/crd/cti_example.yaml
#kubectl -n trusted-identity apply -f deployment/configmap.yaml
TI_SA_TOKEN=$(kubectl -n trusted-identity get sa ti-sa -o jsonpath='{.secrets[0].name}')
cat deployment/configmap.yaml | sed -e "s|\${TI_SA_TOKEN}|${TI_SA_TOKEN}|g" | kubectl -n trusted-identity apply -f -
./deployment/webhook-insecure-cert.sh --namespace trusted-identity

# Create services and deployment
kubectl -n trusted-identity apply -f deployment/service.yaml
kubectl -n trusted-identity apply -f deployment/deployment.yaml

kubectl label namespace trusted-identity tsi-mutate=enabled --overwrite
