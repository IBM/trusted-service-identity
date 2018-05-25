#!/bin/bash

cd "$( dirname "${BASH_SOURCE[0]}")"
kubectl create namespace trusted-identity

kubectl -n trusted-identity delete -f deployment/deployment.yaml


# Create rbac bindings
kubectl -n trusted-identity create deployment/tiRBAC.yaml
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

kubectl label namespace trusted-identity sidecar-injector=enabled --overwrite
