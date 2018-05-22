#!/bin/bash

cd "$( dirname "${BASH_SOURCE[0]}")"

# Create configs and keys
kubectl apply -f deployment/configmap.yaml
kubectl apply -f deployment/nginxconfigmap.yaml
./deployment/webhook-insecure-cert.sh

# Create services and deployment
kubectl apply -f deployment/service.yaml
kubectl apply -f deployment/deployment.yaml
