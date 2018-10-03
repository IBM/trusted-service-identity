#!/bin/bash

# if helm installed, remove the TI deployment
if [ -x "$(command -v helm)" ]; then
  echo "Helm installed"
  helm ls --all | grep ti-key-release | awk '{print $1}' | sort -r| xargs helm delete --purge
else "Helm NOT installed"
fi

kubectl -n trusted-identity delete -f examples/myubuntu_inject.yaml
kubectl -n trusted-identity delete -f examples/web-service.yaml
kubectl -n trusted-identity delete -f examples/jwt-policy-example.yaml

kubectl -n trusted-identity delete -f deployment/revoker-deployment.yaml
kubectl -n trusted-identity delete -f deployment/deployment.yaml
kubectl -n trusted-identity delete -f deployment/service.yaml
kubectl -n trusted-identity delete -f deployment/configmap.yaml
kubectl -n trusted-identity delete -f deployment/crd/cti_example.yaml
kubectl -n trusted-identity delete -f deployment/crd/crd_clusterinfo.yaml
kubectl -n trusted-identity delete -f deployment/tiRBAC.yaml
kubectl -n trusted-identity delete secret ti-keys-config
kubectl delete ns trusted-identity
