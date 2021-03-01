#!/bin/bash
# get the SCRIPT and TSI ROOT directories
SCRIPT_PATH=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
TSI_ROOT="${SCRIPT_PATH}/.."
TSI_VERSION=$(cat ${SCRIPT_PATH}/../tsi-version.txt)

CLUSTERNAME="$1"
PROJECT="${2:-spire-server}"
SPIRESERVER="spire-server"
SPIREGROUP="spiregroup"
SPIRESA="spire-server"
SPIRESCC="spire-server"

## create help menu:
helpme()
{
  cat <<HELPMEHELPME
Install SPIRE server for TSI

Syntax: ${0} <CLUSTER_NAME> <PROJECT_NAME>

Where:
  CLUSTER_NAME - name of the OpenShift cluster (required)
  PROJECT_NAME - OpenShift project [namespace] to install the Server, default: spire-server (optional)
HELPMEHELPME
}

# validate the arguments
if [[ "$1" == "-?" || "$1" == "-h" || "$1" == "--help" ]] ; then
  helpme
  exit 0
elif [[ "$1" == "" ]] ; then
  echo "CLUSTER_NAME is missing"
  helpme
  exit 1
fi

installSpireServer(){

  oc get projects | grep $PROJECT
  if [ "$?" == "0" ]; then
    # check if spire-server project exists:
    echo "$PROJECT project already exists. "
    read -n 1 -r -p "Do you want to re-install it? [y/n]" REPLY
    echo # create a new line
    if [[ $REPLY =~ ^[Yy]$ || $REPLY == "" ]] ; then
      echo "Re-installing $PROJECT project"
      # oc delete project $PROJECT
      cleanup
      while (oc get projects | grep $PROJECT); do echo "Waiting for $PROJECT removal to complete"; sleep 2; done
      oc new-project $PROJECT --description="My TSI Spire SERVER project on OpenShift" > /dev/null
      oc project $PROJECT
    else
      echo "Keeping the existing $PROJECT project as is"
      echo 0
    fi
  else
    oc new-project $PROJECT --description="My TSI Spire SERVER project on OpenShift" > /dev/null
    oc project $PROJECT
  fi

# create serviceAccount and setup permissions
oc create sa $SPIRESA
oc policy add-role-to-user cluster-admin system:serviceaccount:$PROJECT:$SPIRESA
oc adm groups new $SPIREGROUP $SPIRESA

oc apply -f- <<EOF
kind: SecurityContextConstraints
apiVersion: v1
metadata:
  name: $SPIRESCC
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
oc describe scc $SPIRESCC

helm install --set namespace=$PROJECT --set clustername=$CLUSTERNAME spire-server charts/spire-server --debug
helm list

# oc -n $PROJECT expose svc/$SPIRESERVER
oc -n $PROJECT create route passthrough --service spire-server
oc -n $PROJECT get route
INGRESS=$(oc -n $PROJECT get route $SPIRESERVER -o jsonpath='{.spec.host}{"\n"}')
echo $INGRESS

# alternatively:
ING=$(ibmcloud oc cluster get --cluster "$CLUSTERNAME" --output json | jq -r '.ingressHostname')
INGSEC=$(ibmcloud oc cluster get --cluster "$CLUSTERNAME" --output json | jq -r '.ingressSecretName')
INGSTATUS=$(ibmcloud oc cluster get --cluster "$CLUSTERNAME" --output json | jq -r '.ingressStatus')
ibmcloud oc cluster get --cluster "$CLUSTERNAME" --output json | jq -r '.ingressMessage'

# setup TLS secret:
CRN=$(ibmcloud oc ingress secret get -c "$CLUSTERNAME" --name "$INGSEC" --namespace openshift-ingress --output json | jq -r '.crn')
ibmcloud oc ingress secret create --cluster "$CLUSTERNAME" --cert-crn "$CRN" --name "$INGSEC" --namespace $PROJECT
if [ "$?" == "0" ]; then
  echo "All good"
fi

# create ingress deployment:
oc create -f- <<EOF
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: spireingress
spec:
  tls:
  - hosts:
    - $INGRESS
    secretName: $INGSEC
  rules:
  - host: $INGRESS
    http:
      paths:
      - path: /
        backend:
          serviceName: spire-server
          servicePort: 8081
EOF

SPIRESERV=$(oc get route spire-server --output json |  jq -r '.spec.host')
echo "https://$SPIRESERV"
echo
echo "spireServer: $SPIRESERV"
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
  echo "Get `oc` cli from https://mirror.openshift.com/pub/openshift-v4/clients/oc/4.3/"
  exit 1
fi

kubectl_test_cmd="kubectl version"
if [[ $(eval $kubectl_test_cmd) ]]; then
  echo "kubectl client setup properly"
else
  echo "kubectl client must be installed and configured."
  echo "(https://kubernetes.io/docs/tasks/tools/install-kubectl/)"
  exit 1
fi

# This install requires helm verion 3:
helm_test_cmd="helm version --client | grep 'Version:\"v3'"
if [[ $(eval $helm_test_cmd) ]]; then
  echo "helm client v3 installed properly"
else
  echo "helm client v3 must be installed and configured. "
  echo "(https://helm.sh/docs/intro/install/)"
  exit 1
fi

# This install requires helm verion 3:
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
  helm uninstall spire-server -n $PROJECT
  oc delete scc $SPIRESCC --ignore-not-found=true
  oc delete sa $SPIRESA --ignore-not-found=true
  #oc delete group $GROUPNAME --ignore-not-found=true
  oc delete project $PROJECT --ignore-not-found=true
}

checkPrereqs
installSpireServer
