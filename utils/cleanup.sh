#!/bin/bash

# if helm installed, remove the TI deployment
if [ -x "$(command -v helm)" ]; then
  echo "Helm installed"
  helm ls --all | grep ti-key-release | awk '{print $1}' | sort -r| xargs helm delete --purge 2> /dev/null
  helm ls --all | grep tsi-node-setup | awk '{print $1}' | sort -r| xargs helm delete --purge 2> /dev/null
else "Helm NOT installed"
fi

kubectl -n trusted-identity delete -f examples/myubuntu.yaml 2> /dev/null
kubectl -n trusted-identity delete -f examples/web-service.yaml 2> /dev/null
kubectl -n trusted-identity delete -f examples/jwt-policy-example.yaml 2> /dev/null

kubectl -n trusted-identity delete -f deployment/deployment.yaml 2> /dev/null
kubectl -n trusted-identity delete -f deployment/service.yaml 2> /dev/null
kubectl -n trusted-identity delete -f deployment/configmap.yaml 2> /dev/null
kubectl -n trusted-identity delete -f deployment/crd/cti_example.yaml 2> /dev/null
kubectl -n trusted-identity delete -f deployment/crd/crd_clusterinfo.yaml 2> /dev/null
kubectl -n trusted-identity delete -f deployment/tiRBAC.yaml 2> /dev/null
kubectl -n trusted-identity delete secret ti-keys-config 2> /dev/null
kubectl delete ns trusted-identity 2> /dev/null
