#!/bin/bash

cd "$( dirname "${BASH_SOURCE[0]}")"


if [ ! -d "keys/" ]; then
    echo "ERROR: keys/ directory doesn't exist"
    exit 1
  # Control will enter here if $DIRECTORY doesn't exist.
fi

kubectl create namespace trusted-identity

kubectl -n trusted-identity delete secret ti-keys-config


kubectl -n trusted-identity delete -f deployment/deployment.yaml
kubectl -n trusted-identity delete -f deployment/revoker-deployment.yaml

# Check 
kubectl -n trusted-identity create secret generic ti-keys-config --from-file=keys/

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
kubectl -n trusted-identity apply -f deployment/revoker-deployment.yaml

kubectl label namespace trusted-identity ti-injector=enabled --overwrite
