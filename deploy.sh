#!/bin/bash

cd "$( dirname "${BASH_SOURCE[0]}")"

kubectl delete -f deployment/deployment.yaml

# Create configs and keys
kubectl apply -f deployment/crd/crd_clusterinfo.yaml
kubectl apply -f deployment/crd/cti_example.yaml
kubectl apply -f deployment/configmap.yaml
kubectl apply -f deployment/nginxconfigmap.yaml
./deployment/webhook-insecure-cert.sh

# Create services and deployment
kubectl apply -f deployment/service.yaml
kubectl apply -f deployment/deployment.yaml

kubectl label namespace default sidecar-injector=enabled --overwrite
