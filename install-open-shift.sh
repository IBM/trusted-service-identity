#!/bin/bash

# Required Parameters
VAULT_ADDR=http://ti-test1.eu-de.containers.appdomain.cloud
# VAULT_ADDR=
CLUSTER_NAME="ti-test1"
# CLUSTER_NAME=
CLUSTER_REGION="eu-de"
# CLUSTER_REGION=
# For JSS_TYPE: `vtpm2-server` or `jss-server`
JSS_TYPE=vtpm2-server
# JSS_TYPE=



PROJECTNAME="trusted-identity"
SANAME="tsi-setup-admin-sa"
GROUPNAME="tsi-admin-group"
SCCHOST="hostpath"
SCCPOD="genericpod"


checkPrereqs(){
  oc_test_cmd="oc status"
  kubectl_test_cmd="kubectl version"
  helm_test_cmd="helm version --client"

if [[ "$VAULT_ADDR" == "" || "$CLUSTER_NAME" == "" || "$CLUSTER_REGION" == "" || "$JSS_TYPE" == "" ]] ; then
  echo "One of the required paramters is not set! (VAULT_ADDR, CLUSTER_NAME, CLUSTER_REGION, JSS_TYPE)"
  exit 1
fi

if [[ $(eval $oc_test_cmd) ]]; then
  echo "op client setup properly"
else
  echo "op client must be installed and configured."
  echo "Get `oc` cli https://mirror.openshift.com/pub/openshift-v4/clients/oc/4.3/macosx/"
  exit 1
fi

if [[ $(eval $kubectl_test_cmd) ]]; then
  echo "kubectl client setup properly"
else
  echo "kubectl client must be installed and configured."
  exit 1
fi

if [[ $(eval $helm_test_cmd) ]]; then
  echo "helm client setup properly"
else
  echo "helm client must be installed and configured."
  exit 1
fi

}

setupOpenShiftProject() {
# first cleanup everything:
cleanup
echo "waiting 15s for the cleanup to complete..."
sleep 15
read -n 1 -s -r -p 'Press any key to continue'

oc new-project $PROJECTNAME --description="My TSI project on OpenShift" > /dev/null
oc project $PROJECTNAME

# create a service account with admin privilages
oc create sa $SANAME
oc policy add-role-to-user cluster-admin system:serviceaccount:$PROJECTNAME:$SANAME
oc adm groups new $GROUPNAME $SANAME
}

cleanup() {
  oc delete scc $SCCHOST
  oc delete scc $SCCPOD
  oc delete sa $SANAME
  oc delete group $GROUPNAME
  oc delete project $PROJECTNAME
}

createSCCs() {
# create SCC for Installation
oc create -f- <<EOF
kind: SecurityContextConstraints
apiVersion: v1
metadata:
  name: $SCCHOST
allowHostDirVolumePlugin: true
allowPrivilegedContainer: true
allowHostPorts: true
runAsUser:
  type: RunAsAny
seLinuxContext:
  type: RunAsAny
fsGroup:
  type: RunAsAny
supplementalGroups:
  type: RunAsAny
groups:
- $GROUPNAME
EOF
oc describe scc $SCCHOST

# create SCC for Generic Pods
oc create -f- <<EOF
kind: SecurityContextConstraints
apiVersion: v1
metadata:
  name: $SCCPOD
allowHostDirVolumePlugin: true
allowPrivilegedContainer: false
runAsUser:
  type: RunAsAny
seLinuxContext:
  type: RunAsAny
fsGroup:
  type: RunAsAny
supplementalGroups:
  type: RunAsAny
groups:
- system:authenticated
EOF
oc describe scc $SCCPOD
}

executeNodeSetup() {
# to list the chart values:
# helm inspect values charts/tsi-node-setup/
helm template charts/tsi-node-setup/ --name tsi-setup --set reset.all=false \
--set reset.x5c=false > tsi-node-setup.yaml
oc apply -f tsi-node-setup.yaml
}

executeInstall-1() {

# to list the chart values:
# helm inspect values charts/ti-key-release-1/
helm template charts/ti-key-release-1/ --name tsi-1 --set vaultAddress=$VAULT_ADDR \
--set cluster.name=$CLUSTER_NAME --set cluster.region=$CLUSTER_REGION > tsi-install-1.yaml
oc apply -f tsi-install-1.yaml
# add the `ti-install-sa` to admin group
oc policy add-role-to-user cluster-admin system:serviceaccount:trusted-identity:ti-install-sa
}

executeInstall-2() {

# since we are not using nested helm charts, and set-1 is already executed,
# remove it from teh set-2:
rm charts/ti-key-release-2/charts/ti-key-release-1*
mv charts/ti-key-release-2/requirements.* charts/

# to list the chart values:
# helm inspect values charts/ti-key-release-2/
helm template charts/ti-key-release-2/ --name tsi-2 \
--set ti-key-release-1.vaultAddress=$VAULT_ADDR \
--set ti-key-release-1.cluster.name=$CLUSTER_NAME \
--set ti-key-release-1.cluster.region=$CLUSTER_REGION \
--set jssService.type=$JSS_TYPE > tsi-install-2.yaml

oc apply -f tsi-install-2.yaml
}


checkPrereqs
setupOpenShiftProject
createSCCs
executeNodeSetup
read -n 1 -s -r -p 'Press any key to continue'
executeInstall-1
read -n 1 -s -r -p 'Press any key to continue'
executeInstall-2
