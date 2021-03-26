#!/bin/bash

# SPIRE Server info:
SPIRESERVERPROJECT="tornjak"
CLUSTERNAME=$1
SPIRESERVER=$2
# SPIRE Agent info:
TRUSTDOMAIN="${3:-spiretest.com}"
PROJECT="${4:-spire}"
SPIREGROUP="spiregroup"
SPIREAGSA="spire-agent"
SPIREAGSCC="spire-agent"

## create help menu:
helpme()
{
  cat <<HELPMEHELPME
Install SPIRE agent and workload registrar for TSI

Syntax: ${0} <CLUSTER_NAME> <SPIRE_SERVER> <PROJECT_NAME>

Where:
  CLUSTER_NAME - name of the OpenShift cluster (required)
  SPIRE_SERVER - SPIRE server end-point (required)
  TRUST_DOMAIN - the trust root of SPIFFE identity provider, default: spiretest.com (optional)
  PROJECT_NAME - OpenShift project [namespace] to install the Agent, default: spire (optional)
HELPMEHELPME
}

# validate the arguments
if [[ "$1" == "-?" || "$1" == "-h" || "$1" == "--help" ]] ; then
  helpme
  exit 0
elif [[ "$2" == "" ]] ; then
  echo "Both CLUSTER_NAME and SPIRE_SERVER are required"
  helpme
  exit 1
fi

# function for executing oc cli calls
oc_cli() {
oc "$@"
if [ "$?" != "0" ]; then
  echo "Error executing: oc" "$@"
  exit 1
fi
}

installSpireAgent(){
  oc get projects | grep "${PROJECT}"
  if [ "$?" == "0" ]; then
    # check if spire-agent project exists:
    echo "$PROJECT project already exists. "
    read -n 1 -r -p "Do you want to re-install it? [y/n]" REPLY
    echo # create a new line
    if [[ $REPLY =~ ^[Yy]$ || $REPLY == "" ]] ; then
      echo "Re-installing $PROJECT project"
      # oc delete project $PROJECT
      cleanup
      while (oc get projects | grep -v spire-server | grep "$PROJECT"); do echo "Waiting for $PROJECT removal to complete"; sleep 2; done
      oc new-project "$PROJECT" --description="My TSI Spire Agent project on OpenShift" > /dev/null
      oc project "$PROJECT"
    else
      echo "Keeping the existing $PROJECT project as is"
    fi
  else
    oc new-project "$PROJECT" --description="My TSI Spire Agent project on OpenShift" > /dev/null
    oc project "$PROJECT"
  fi

# Need to copy the spire-bundle from the server namespace
oc_cli get configmap spire-bundle -n "$SPIRESERVERPROJECT" -o yaml | sed "s/namespace: $SPIRESERVERPROJECT/namespace: $PROJECT/" | oc apply -n "$PROJECT" -f -

oc_cli create sa $SPIREAGSA
oc_cli adm groups add-users $SPIREGROUP $SPIREAGSA

oc_cli create -f- <<EOF
kind: SecurityContextConstraints
apiVersion: v1
metadata:
  name: $SPIREAGSCC
allowHostIPC: true
allowHostNetwork: true
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
- system:authenticated
EOF
oc_cli describe scc $SPIREAGSCC

oc_cli adm policy add-scc-to-user spire-agent "system:serviceaccount:$PROJECT:$SPIREAGSA"

# this works:
oc_cli adm policy add-scc-to-user privileged -z $SPIREAGSA

helm install --set "spireAddress=$SPIRESERVER" --set "namespace=$PROJECT" \
 --set "clustername=$CLUSTERNAME" --set "trustdomain=$TRUSTDOMAIN" spire charts/spire --debug

cat << EOF

Next, login to the SPIRE Server and register the Workload Registrar
to gain admin access to the server.

oc exec -it spire-server-0 -n $SPIRESERVERPROJECT -- sh

 A few, sample server commands:

# show entries:
/opt/spire/bin/spire-server entry show -registrationUDSPath /run/spire/sockets/registration.sock
# show agents:
/opt/spire/bin/spire-server agent list -registrationUDSPath /run/spire/sockets/registration.sock
# delete entry:
/opt/spire/bin/spire-server entry delete -registrationUDSPath /run/spire/sockets/registration.sock --entryID

# sample Registrar reqistration:
/opt/spire/bin/spire-server entry create -admin \
-selector k8s:sa:spire-k8s-registrar \
-selector k8s:ns:$PROJECT \
-selector k8s:container-image:gcr.io/spiffe-io/k8s-workload-registrar@sha256:912484f6c0fb40eafb16ba4dd2d0e1b0c9d057c2625b8ece509f5510eaf5b704 \
-selector k8s:container-name:k8s-workload-registrar \
-spiffeID spiffe://${TRUSTDOMAIN}/workload-registrar \
-parentID spiffe://${TRUSTDOMAIN}/spire/agent/k8s_psat/$CLUSTERNAME/b9e0af7a-bdbf-4e23-a3ec-cf2a61885c37 \
-registrationUDSPath /tmp/registration.sock

# sample Registrar registration with just a subset of selectors:
/opt/spire/bin/spire-server entry create -admin \
-selector k8s:ns:$PROJECT \
-selector k8s:container-name:k8s-workload-registrar \
-spiffeID spiffe://${TRUSTDOMAIN}/workload-registrar \
-parentID spiffe://${TRUSTDOMAIN}/spire/agent/k8s_psat/$CLUSTERNAME/b9e0af7a-bdbf-4e23-a3ec-cf2a61885c37 \
-registrationUDSPath /tmp/registration.sock

# Create Entry in Tornjak:
SPIFFE ID:
spiffe://${TRUSTDOMAIN}/$CLUSTERNAME/workload-registrarX
Parent ID:
spiffe://${TRUSTDOMAIN}/spire/agent/k8s_psat/$CLUSTERNAME/b9e0af7a-bdbf-4e23-a3ec-cf2a61885c37
Selectors:
k8s:sa:spire-k8s-registrar,k8s:ns:$PROJECT,k8s:container-name:k8s-workload-registrar
* check Admin Flag

EOF
}

checkPrereqs(){

jq_test_cmd="jq --version"
if [[ $(eval $jq_test_cmd) ]]; then
  echo "jq client setup properly"
else
  echo "jq client must be installed and configured."
  echo "(https://stedolan.github.io/jq/)"
  exit 1
fi

oc_test_cmd="oc status"
if [[ $(eval $oc_test_cmd) ]]; then
  echo "oc client setup properly"
else
  echo "oc client must be installed and configured."
  echo "(https://docs.openshift.com/container-platform/4.2/cli_reference/openshift_cli/getting-started-cli.html)"
  echo "Get 'oc' cli from https://mirror.openshift.com/pub/openshift-v4/clients/oc/4.3/"
  exit 1
fi

# make sure k8s server is at least v1.18, to support
# projected ServiceAccountTokens
# sample: "gitVersion": "v1.18.3+e574db2",
k8sver=$(oc version --output json | jq -r '.serverVersion.gitVersion' |grep "v1."| cut -d'.' -f 2)
if [ "$k8sver" -ge 18 ]; then
  echo "Kubernetes server version is correct"
else
  echo "To support functionality like projected ServiceAccountTokens, required Kubernetes version is at least v1.18+"
  exit 1
fi

# kubectl_test_cmd="kubectl version"
# if [[ $(eval $kubectl_test_cmd) ]]; then
#   echo "kubectl client setup properly"
# else
#   echo "kubectl client must be installed and configured."
#   echo "(https://kubernetes.io/docs/tasks/tools/install-kubectl/)"
#   exit 1
# fi

# This install requires helm verion 3:
helm_test_cmd="helm version --client| grep 'Version:\"v3'"
if [[ $(eval $helm_test_cmd) ]]; then
  echo "helm client v3 installed properly"
else
  echo "helm client v3 must be installed and configured. "
  echo "(https://helm.sh/docs/intro/install/)"
  exit 1
fi

# This install requires ibmcloud cli with oc plugin:
ibmcloud_test_cmd="ibmcloud oc versions"
if [[ $(eval $ibmcloud_test_cmd) ]]; then
  echo "ibmcloud oc installed properly"
else
  echo "ibmcloud cli with oc plugin must be installed and configured. "
  echo "(https://cloud.ibm.com/docs/openshift?topic=openshift-openshift-cli)"
  exit 1
fi

}

cleanup() {
  helm uninstall spire -n $PROJECT 2>/dev/null
  oc delete ClusterRole spire-agent-cluster-role spire-k8s-registrar-cluster-role 2>/dev/null
  oc delete ClusterRoleBinding spire-agent-cluster-role-binding spire-k8s-registrar-cluster-role-binding 2>/dev/null
  oc delete scc $SPIREAGSCC 2>/dev/null
  oc delete sa $SPIREAGSA 2>/dev/null
  oc delete project $PROJECT 2>/dev/null
}

checkPrereqs
installSpireAgent
