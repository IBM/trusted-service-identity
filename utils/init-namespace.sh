#!/bin/bash

while kubectl get ns trusted-identity | grep Terminating; do sleep 5;done
kubectl create namespace trusted-identity
