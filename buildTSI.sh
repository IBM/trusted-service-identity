#!/bin/bash

# setup common code:
source ./buildTSI-setup.sh $1 $2

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
