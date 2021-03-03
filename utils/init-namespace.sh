#!/bin/bash

while kubectl get ns trusted-identity 2> /dev/null | grep Terminating; do sleep 5;done
kubectl create namespace trusted-identity
