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
run "make $ALL$PUSH -C components/jwt-init/"
run "make $ALL$PUSH -C components/node-setup/"
run "make $ALL$PUSH -C components/vault-plugin/"

# Helm chart packaging:
run "helm --debug package --app-version ${TSI_VERSION} --version ${TSI_VERSION} charts/tsi-node-setup"
run "helm --debug package --app-version ${TSI_VERSION} --version ${TSI_VERSION} charts/ti-key-release-1"


# even though the chart version can be passed dynamically as above,
# to use the dependency chart, the version must be specified in Chart file :-(
cat > "./charts/ti-key-release-1/Chart.yaml" << EOF
apiVersion: v1
description: A Helm chart for deployment of TI-KeyRelease [1/2]
name: ti-key-release-1
home: https://github.com/IBM/trusted-service-identity
version: ${TSI_VERSION}
appVersion: ${TSI_VERSION}
maintainers:
  - name: Brandon Lum
    email: Brandon.Lum@ibm.com
  - name: Mariusz Sabath
    email: sabath@us.ibm.com
EOF

# this is not required, as this chart today is not a dependency for anything else
# but to be consistent with the above...
cat > "./charts/ti-key-release-2/Chart.yaml" << EOF
apiVersion: v1
description: A Helm chart for deployment of TI-KeyRelease [2/2]
name: ti-key-release-2
home: https://github.com/IBM/trusted-service-identity
version: ${TSI_VERSION}
appVersion: ${TSI_VERSION}
maintainers:
  - name: Brandon Lum
    email: Brandon.Lum@ibm.com
  - name: Mariusz Sabath
    email: sabath@us.ibm.com
EOF

# setup the dependency file
cat > "./charts/ti-key-release-2/requirements.yaml" << EOF
dependencies:
  - name: ti-key-release-1
    version: ${TSI_VERSION}
    repository: "file://../ti-key-release-1"
EOF

run "helm --debug dep update charts/ti-key-release-2"
run "helm --debug package --dependency-update --app-version ${TSI_VERSION} --version ${TSI_VERSION}  charts/ti-key-release-2"

mv *.tgz charts/

# render the Vault deployment from a template
EXAMPLES_DIR=examples/vault
sed "s/<%TSI_VERSION%>/$TSI_VERSION/g" ${EXAMPLES_DIR}/vault.tpl > ${EXAMPLES_DIR}/vault.yaml
