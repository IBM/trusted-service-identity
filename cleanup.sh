#!/bin/bash

kubectl -n trusted-identity delete -f deployment/revoker-deployment.yaml
kubectl -n trusted-identity delete -f deployment/deployment.yaml
kubectl -n trusted-identity delete -f deployment/service.yaml
kubectl -n trusted-identity delete -f deployment/configmap.yaml
kubectl -n trusted-identity delete -f deployment/crd/cti_example.yaml
kubectl -n trusted-identity delete -f deployment/crd/crd_clusterinfo.yaml
kubectl -n trusted-identity delete -f deployment/tiRBAC.yaml
kubectl -n trusted-identity delete secret ti-keys-config
kubectl delete ns trusted-identity
