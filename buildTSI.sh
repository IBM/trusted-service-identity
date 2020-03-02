#!/bin/bash

ALL="$ALL"

if [ "$1" == "fast" ]; then
   ALL="fast"
fi
# if [ "$KUBECONFIG" == "" ]; then
#   echo "KUBECONFIG must be set!"
#   exit 1
# fi

run() {
  local CMD=$1
  $CMD
  RT=$?
  if [ $RT -ne 0 ] ; then
     echo "($CMD) failed!"
     exit 1
  fi
}


run "make all"
run "make docker-push"
run "make $ALL -C components/jss/"
run "make $ALL -C components/jwt-sidecar/"
run "make $ALL -C components/node-setup/"
run "make $ALL -C examples/vault-client/"
run "make all -C examples/vault-plugin/"
run "helm package charts/tsi-node-setup"
run "helm package charts/ti-key-release-1"
run "helm dep update charts/ti-key-release-2"
run "helm package --dependency-update charts/ti-key-release-2"

mv *.tgz charts/
