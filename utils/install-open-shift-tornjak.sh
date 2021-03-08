#!/bin/bash
# get the SCRIPT and TSI ROOT directories
SCRIPT_PATH=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
TSI_ROOT="${SCRIPT_PATH}/.."
TSI_VERSION=$(cat ${SCRIPT_PATH}/../tsi-version.txt)

CLUSTERNAME="$1"
TRUSTD="${2:-spiretest.com}"
PROJECT="${3:-tornjak}"
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
  TRUST_DOMAIN - the trust root of SPIFFE identity provider, default: spiretest.com (optional)
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
      oc new-project $PROJECT --description="My TSI Spire SERVER project on OpenShift" 2> /dev/null
      oc project $PROJECT
    else
      echo "Keeping the existing $PROJECT project as is"
      echo 0
    fi
  else
    oc new-project $PROJECT --description="My TSI Spire SERVER project on OpenShift" 2> /dev/null
    oc project $PROJECT
  fi

# create serviceAccount and setup permissions
oc create sa $SPIRESA
oc policy add-role-to-user cluster-admin system:serviceaccount:$PROJECT:$SPIRESA
oc adm groups new $SPIREGROUP $SPIRESA 2> /dev/null

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

# get ingress information:
ING=$(ibmcloud oc cluster get --cluster "$CLUSTERNAME" --output json | jq -r '.ingressHostname')
INGSEC=$(ibmcloud oc cluster get --cluster "$CLUSTERNAME" --output json | jq -r '.ingressSecretName')
INGSTATUS=$(ibmcloud oc cluster get --cluster "$CLUSTERNAME" --output json | jq -r '.ingressStatus')
ibmcloud oc cluster get --cluster "$CLUSTERNAME" --output json | jq -r '.ingressMessage'


# add the certs and keys
#here=$(pwd)
#cd /Users/sabath/workspace/mrsabath/tornjak/sample-keys
# ./gen_domain.sh *.tsi-roks02-5240a919746a818fd9d58aa25c34ecfe-0000.eu-de.containers.appdomain.cloud $CLUSTERNAME
#$SCRIPT_PATH/gen_domain.sh "*.$ING" $CLUSTERNAME
echo "Generating certs..."
openssl req -new -x509 -sha256 -key "$SCRIPT_PATH/../sample-keys/key.pem" -subj "/C=US/ST=CA/O=Acme, Inc./CN=example.com" -extensions SAN -config <(cat "$SCRIPT_PATH/../sample-keys/openssl.cnf" <(printf "[SAN]\nsubjectAltName=DNS:*.${ING},DNS:example.com,DNS:www.example.com")) -out "$SCRIPT_PATH/../sample-keys/$CLUSTERNAME.pem"
# store the certs in the secret
oc -n tornjak create secret generic tornjak-certs \
 --from-file="$SCRIPT_PATH/../sample-keys/key.pem" \
 --from-file=cert.pem="$SCRIPT_PATH/../sample-keys/$CLUSTERNAME.pem" \
 --from-file=tls.pem="$SCRIPT_PATH/../sample-keys/$CLUSTERNAME.pem" \
 --from-file=mtls.pem="$SCRIPT_PATH/../sample-keys/$CLUSTERNAME.pem"
# cd $here

# run helm install for the tornjak server
helm install --set namespace=$PROJECT --set clustername=$CLUSTERNAME --set trustdomain=$TRUSTD tornjak charts/tornjak # --debug
helm list

# oc -n $PROJECT expose svc/$SPIRESERVER
# Ingress route for spire-server
oc -n $PROJECT create route passthrough --service spire-server
oc -n $PROJECT get route
INGRESS=$(oc -n $PROJECT get route spire-server -o jsonpath='{.spec.host}{"\n"}')
echo $INGRESS

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

# create route for Tornjak TLS:
oc -n $PROJECT create route passthrough tornjak-tls --service tornjak-tls
# create route for Tornjak mTLS:
oc -n $PROJECT create route passthrough tornjak-mtls --service tornjak-mtls
# create route for Tornjak HTTP:
# oc create route passthrough tornjak-http --service tornjak-http
oc -n $PROJECT expose svc/tornjak-http

SPIRESERV=$(oc get route spire-server --output json |  jq -r '.spec.host')
echo # "https://$SPIRESERV"
echo "export SPIRESERVER=$SPIRESERV"
echo # empty line to separate visually

TORNJAKHTTP=$(oc get route tornjak-http --output json |  jq -r '.spec.host')
echo "Tornjak (http): http://$TORNJAKHTTP/"
TORNJAKTLS=$(oc get route tornjak-tls --output json |  jq -r '.spec.host')
echo "Tornjak (TLS): https://$TORNJAKTLS/"
TORNJAKMTLS=$(oc get route tornjak-mtls --output json |  jq -r '.spec.host')
echo "Tornjak (mTLS): https://$TORNJAKMTLS/"
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

# kubectl_test_cmd="kubectl version"
# if [[ $(eval $kubectl_test_cmd) ]]; then
#   echo "kubectl client setup properly"
# else
#   echo "kubectl client must be installed and configured."
#   echo "(https://kubernetes.io/docs/tasks/tools/install-kubectl/)"
#   exit 1
# fi

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
  helm uninstall spire-server -n $PROJECT 2>/dev/null
  oc delete ClusterRole spire-server-role 2>/dev/null
  oc delete ClusterRoleBinding spire-server-binding 2>/dev/null

  oc delete scc $SPIRESCC 2>/dev/null
  oc delete sa $SPIRESA 2>/dev/null
  #oc delete group $GROUPNAME --ignore-not-found=true
  oc delete project $PROJECT 2>/dev/null
}

checkPrereqs
installSpireServer
