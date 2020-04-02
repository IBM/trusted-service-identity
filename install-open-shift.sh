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

if [[ "$KUBECONFIG" == "" ]] ; then
  echo "KUBECONFIG, pointing at OpenShift cluster, must be set"
  exit 1
fi

if [[ $(eval $oc_test_cmd) ]]; then
  echo "op client setup properly"
else
  echo "op client must be installed and configured."
  echo "(https://docs.openshift.com/container-platform/4.2/cli_reference/openshift_cli/getting-started-cli.html)"
  echo "Get `oc` cli from https://mirror.openshift.com/pub/openshift-v4/clients/oc/4.3/"
  exit 1
fi

if [[ $(eval $kubectl_test_cmd) ]]; then
  echo "kubectl client setup properly"
else
  echo "kubectl client must be installed and configured."
  echo "(https://kubernetes.io/docs/tasks/tools/install-kubectl/)"
  exit 1
fi

if [[ $(eval $helm_test_cmd) ]]; then
  echo "helm client setup properly"
else
  echo "helm client must be installed and configured. "
  echo "(https://helm.sh/docs/intro/install/)"
  exit 1
fi

}

setupOpenShiftProject() {
# first cleanup everything:
cleanup
echo ""
echo "To track the status, you can start another console with appropriate KUBECONFIG "
echo "Then run:"
echo "    watch -n 5 kubectl -n trusted-identity get all"
echo "waiting 15s for the cleanup to complete..."
sleep 15

read -n 1 -s -r -p 'When cleanup completed, press any key to continue'

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
echo ""
echo "Wait for the setup pods in Running state"
read -n 1 -s -r -p 'Press any key to continue'
executeInstall-1
echo ""
echo "Wait for all Running or Completed"
read -n 1 -s -r -p 'Press any key to continue'
executeInstall-2
echo ""
echo "Wait for all Running or Completed"
echo "*** One time initial bootstrapping setup required ***"
echo "For complete setup description please visit: "
echo "  https://github.com/IBM/trusted-service-identity/blob/master/examples/vault-plugin/README.md#register-jwt-signing-service-jss-with-vault"
echo ""
echo "This process assumes Vault is already setup at another location as described: "
echo "  https://github.com/IBM/trusted-service-identity#setup-vault"
echo ""
echo "1. change directory to examples/vault-plugin:"
echo "    cd examples/vault-plugin"
echo "2. test the connection to Vault:"
echo "    curl $VAULT_ADDR"
echo "  expected result: <a href=\"/ui/\">Temporary Redirect</a>"
echo "3. obtain the ROOT_TOKEN from the cluster with running Vault and export it"
echo "    export ROOT_TOKEN="
echo "4. setup shortcut alias:"
echo "    alias kk=\"kubectl -n trusted-identity\" "
echo "5. test whether CSRs can be retrieved:"
echo '    kk exec -it $(kk get po | grep tsi-node-setup | awk '"'{print "'$1}'"' |  sed -n 1p ) -- sh -c 'curl"' $HOST_IP:5000/public/getCSR'"'"
echo "6. execute cluster registration with Vault: "
echo "    ./demo.registerJSS.sh"
echo "7. load sample policies:"
echo "    ./demo.load-sample-policies.sh"
echo "8. load sample keys:"
echo "    ./demo.load-sample-keys.sh $CLUSTER_REGION $CLUSTER_NAME"
echo "9. the setup containers can be removed now:"
echo "    kk delete ds tsi-setup-tsi-node-setup "
echo "    kk delete sa tsi-setup-admin-sa"
echo "    oc delete scc $SCCHOST"
echo ""
echo "Now you can test by running the sample pod:"
echo "  kk create -f examples/myubuntu.yaml"
echo "Once running, execute: "
echo '  kk exec -it $(kk get pods | grep myubuntu | awk '"'{print "'$1}'"') cat /tsi-secrets/mysecrets/myubuntu-mysecret1/mysecret1"
echo "********* END ********"
