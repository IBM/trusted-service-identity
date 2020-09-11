#!/bin/bash

TSI_VERSION=$(cat ./tsi-version.txt )

ALL="all"
PUSH=""

if [ "$1" == "fast" ]; then
   ALL="fast"
elif [ "$1" == "push" ]; then
  PUSH="push"
fi

if [ "$2" == "fast" ]; then
   ALL="fast"
elif [ "$2" == "push" ]; then
  PUSH="push"
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


run "make $ALL$PUSH"
run "make $ALL$PUSH -C components/jss/"
run "make $ALL$PUSH -C components/tsi-util/"
run "make $ALL$PUSH -C components/vtpm2-server/"
run "make $ALL$PUSH -C components/jwt-sidecar/"
run "make $ALL$PUSH -C components/node-setup/"
run "make $ALL$PUSH -C components/vault-plugin/"

# render the Vault deployment from a template
EXAMPLES_DIR=examples/vault
sed "s/<%TSI_VERSION%>/$TSI_VERSION/g" ${EXAMPLES_DIR}/vault.tpl > ${EXAMPLES_DIR}/vault.yaml

/bin/bash ./buildTSI-helm.sh
