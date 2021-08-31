#!/bin/bash

# SPIRE Server info:
SPIRE_SERVER_PROJECT="tornjak"
# SPIRE Agent info:
TRUSTDOMAIN="spiretest.com"
PROJECT="spire"
SPIRE_GROUP="spiregroup"
SPIRE_AG_SA="spire-agent"
SPIREAG_SCC="spire-agent"

## create help menu:
helpme()
{
  cat <<HELPMEHELPME
Install SPIRE agent and workload registrar for TSI

Syntax: ${0} -c <CLUSTER_NAME> -s <SPIRE_SERVER> -t <TRUST_DOMAIN> -p <PROJECT_NAME> -r <REGION>

Where:
  -c <CLUSTER_NAME> - name of the OpenShift cluster (required)
  -s <SPIRE_SERVER> - SPIRE server end-point (required)
  -r <REGION>       - region, geo-location (required)
  -t <TRUST_DOMAIN> - the trust root of SPIFFE identity provider, default: spiretest.com (optional)
  -p <PROJECT_NAME> - OpenShift project [namespace] to install the Server, default: spire-server (optional)
  --clean - performs removal of project (allows additional parameters i.e. -p|--project).
HELPMEHELPME
}

cleanup() {
  helm uninstall spire -n $PROJECT 2>/dev/null
  oc delete ClusterRole spire-agent-cluster-role spire-k8s-registrar-cluster-role 2>/dev/null
  oc delete ClusterRoleBinding spire-agent-cluster-role-binding spire-k8s-registrar-cluster-role-binding 2>/dev/null
  oc delete scc $SPIREAG_SCC 2>/dev/null
  oc delete sa $SPIRE_AG_SA 2>/dev/null
  # oc delete project $PROJECT 2>/dev/null
}


POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -c|--cluster)
    CLUSTERNAME="$2"
    shift # past argument
    shift # past value
    ;;
    -s|--server)
    SPIRESERVER="$2"
    shift # past argument
    shift # past value
    ;;
    -t|--trust)
    TRUSTDOMAIN="$2"
    shift # past argument
    shift # past value
    ;;
    -r|--region)
    REGION="$2"
    shift # past argument
    shift # past value
    ;;
    -p|--project)
    PROJECT="$2"
    shift # past argument
    shift # past value
    ;;
    --clean)
    cleanup
    exit 0
    ;;
    -h|--help)
    helpme
    exit 0
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done

# validate the arguments
if [[ "$CLUSTERNAME" == "" ]] ; then
  echo "-c CLUSTER_NAME must be provided"
  helpme
  exit 1
elif [[ "$SPIRESERVER" == "" ]] ; then
  echo "-s SPIRE_SERVER must be provided"
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
  if [ "$?" != "0" ]; then
    echo "Project $PROJECT must be created first"
    echo "oc new-project $PROJECT --description=\"My TSI Spire Agent project on OpenShift\" 2> /dev/null"
    exit 1
  fi

  oc -n $PROJECT get scc $SPIREAG_SCC
  if [ "$?" == "0" ]; then
    # check if spire-agent project exists:
    echo "SPIRE Agent environment in $PROJECT project already exists. "
    read -n 1 -r -p "Do you want to re-install it? [y/n]" REPLY
    echo # create a new line
    if [[ $REPLY =~ ^[Yy]$ || $REPLY == "" ]] ; then
      echo "Re-installing $PROJECT project"
      # oc delete project $PROJECT
      cleanup
      # while (oc get projects | grep -v spire-server | grep "$PROJECT"); do echo "Waiting for $PROJECT removal to complete"; sleep 2; done
      # oc new-project "$PROJECT" --description="My TSI Spire Agent project on OpenShift" > /dev/null
      oc project "$PROJECT"
    else
      echo "Keeping the existing $PROJECT project as is"
    fi
  fi

# Need to copy the spire-bundle from the server namespace
oc -n "$PROJECT" get cm spire-bundle
if [ "$?" == "0" ]; then
  echo "WARNING: using the existing configmap spire-bundle in $PROJECT. "
else
  echo "ConfigMap 'spire-bundle' must be created"
  exit 1
  # echo " oc_cli get configmap spire-bundle -n $SPIRE_SERVER_PROJECT -o yaml | sed \"s/namespace: $SPIRE_SERVER_PROJECT/namespace: $PROJECT/" | oc apply -n "$PROJECT" -f -
fi

# if the group exists, just ignore the error
oc adm groups new "$SPIRE_GROUP" 2> /dev/null

oc create sa $SPIRE_AG_SA 2> /dev/null
oc adm groups add-users $SPIRE_GROUP $SPIRE_AG_SA 2> /dev/null

oc_cli create -f- <<EOF
kind: SecurityContextConstraints
apiVersion: v1
metadata:
  name: $SPIREAG_SCC
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
# oc_cli describe scc $SPIREAG_SCC

oc_cli adm policy add-scc-to-user spire-agent "system:serviceaccount:$PROJECT:$SPIRE_AG_SA"

# this works:
oc_cli adm policy add-scc-to-user privileged -z $SPIRE_AG_SA

helm install --set "spireAddress=$SPIRESERVER" --set "namespace=$PROJECT" \
 --set "clustername=$CLUSTERNAME" --set "trustdomain=$TRUSTDOMAIN" \
 --set "region=$REGION" \
 --set "openShift=true" spire charts/spire # --debug

cat << EOF

Next, login to the SPIRE Server and register the Workload Registrar
to gain admin access to the server.

oc exec -it spire-server-0 -n $SPIRE_SERVER_PROJECT -- sh

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
-registrationUDSPath /run/spire/sockets/registration.sock

# sample Registrar registration with just a subset of selectors:
/opt/spire/bin/spire-server entry create -admin \
-selector k8s:ns:$PROJECT \
-selector k8s:container-name:k8s-workload-registrar \
-spiffeID spiffe://${TRUSTDOMAIN}/workload-registrar \
-parentID spiffe://${TRUSTDOMAIN}/spire/agent/k8s_psat/$CLUSTERNAME/b9e0af7a-bdbf-4e23-a3ec-cf2a61885c37 \
-registrationUDSPath /run/spire/sockets/registration.sock

EOF
}

checkPrereqs(){

# jq is needed for parsing the json output
jq_test_cmd="jq --version"
if [[ $(eval $jq_test_cmd) ]]; then
  echo "jq client setup properly"
else
  echo "jq client must be installed and configured."
  echo "(https://stedolan.github.io/jq/)"
  exit 1
fi

# openshift client
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

checkPrereqs
installSpireAgent
