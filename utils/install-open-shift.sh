#!/bin/bash
# get the SCRIPT and TSI ROOT directories
SCRIPT_PATH=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
TSI_ROOT="${SCRIPT_PATH}/.."
TSI_VERSION=$(cat ${SCRIPT_PATH}/../tsi-version.txt)

# Required Parameters
# CLUSTER_NAME=
# REGION="eu-de"
# For JSS_TYPE: `vtpm2-server` or `jss-server`
JSS_TYPE=vtpm2-server
# JSS_TYPE=
# application namespace: e.g. test
APP_NS="test"
# default vault namespace, if Vault create requested
VAULT_NS="tsi-vault"
# run sidecar. When set to true, the sidecar would periodically retrieve secrets
# from Vault. This supports secret changes or revocation
# when set to felse, secrets are only retrieved once, during the container init
# and they cannot be modified anymore.
# false also support Kubernetes jobs, since the sidecar runs forever and the job
# would never complete.
RUN_SIDECAR="true"


# setup the Cluster Information in IKS
# CL_INFO=$("$SCRIPT_PATH/get-cluster-info.sh")
# echo $CL_INFO > cluster-info.txt
# source cluster-info.txt
# rm cluster-info.txt

PROJECTNAME="trusted-identity"
SANAME="tsi-setup-admin-sa"
GROUPNAME="tsi-admin-group"
SCCHOST="hostpath"
SCCPOD="genericpod"

checkPrereqs(){
  oc_test_cmd="oc status"
  kubectl_test_cmd="kubectl version"
  # today we require helm verion 2:
  helm_test_cmd="helm version --client| grep 'SemVer:\"v2'"

if [[ "$CLUSTER_NAME" == "" || "$REGION" == "" || "$JSS_TYPE" == "" ]] ; then
  echo "One of the required paramters is not set! (CLUSTER_NAME, REGION, JSS_TYPE)"
  exit 1
fi

if [[ $(eval $oc_test_cmd) ]]; then
  echo "oc client setup properly"
else
  echo "oc client must be installed and configured."
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
  echo "helm client v2 installed properly"
else
  echo "helm client v2 must be installed and configured. "
  echo "(https://helm.sh/docs/intro/install/)"
  exit 1
fi

if [[ "$VAULT_ADDR" != "" ]] ; then
  echo "using the provided Vault at $VAULT_ADDR"
else
  echo "VAULT_ADDR is not provided. Would you like to proceed with the default"
  read -n 1 -r -p "Vault installation? [y/n]" REPLY
  echo # create a new line
  if [[ $REPLY =~ ^[Yy]$ || $REPLY == "" ]] ; then
    echo "Installing vault in $VAULT_NS namespace"
    setupVaultNS
  else
    echo "Aborting the installation..."
    exit 1
  fi
fi
}

setupVault() {
  kubectl create -n $VAULT_NS -f $TSI_ROOT/examples/vault/vault.yaml
  kubectl -n tsi-vault wait --for=condition=available --timeout=60s deploy/tsi-vault

  oc -n $VAULT_NS expose svc/tsi-vault
  oc -n $VAULT_NS get route
  VAULTx=$(oc -n $VAULT_NS get route tsi-vault -o jsonpath='{.spec.host}')
  if [ "$?" == "0" ]; then
    VAULT_ADDRx="http://${VAULTx}"
  else
    echo "Vault cannot be properly installed"
    exit 1
  fi
  echo "hold on for 10s to let vault intialize..."
  sleep 10
  $TSI_ROOT/examples/vault/demo.vault-setup.sh $VAULT_ADDRx $VAULT_NS
  if [ "$?" != "0" ]; then
    echo "Vault setup error"
    exit 1
  fi
}

setupVaultNS() {
  kubectl get ns $VAULT_NS
  if [ "$?" == "0" ]; then

    kubectl -n $VAULT_NS get po | grep "tsi-vault" | grep "Running"
    if [ "$?" == "0" ]; then

      echo "Vault instace is already running. "
      read -n 1 -r -p "Do you want to re-install it? [y/n]" REPLY
      echo # create a new line
      if [[ $REPLY =~ ^[Yy]$ || $REPLY == "" ]] ; then
        echo "Re-installing vault in $VAULT_NS namespace"
        kubectl delete ns $VAULT_NS --grace-period=0 --force --wait=true
        kubectl create ns $VAULT_NS
        setupVault
      else
        echo "Keeping the existing Vault instance"
      fi
    else
      setupVault
    fi

  else
    kubectl create ns $VAULT_NS
    setupVault
  fi

  VAULTx=$(oc -n $VAULT_NS get route tsi-vault -o jsonpath='{.spec.host}')
  if [ "$?" == "0" ]; then
    VAULT_ADDR="http://${VAULTx}"
    echo "Vault setup completed. $VAULT_ADDR"
  else
    echo "Vault cannot be properly installed"
    exit 1
  fi

}

setupOpenShiftProject() {
# first cleanup everything:
cleanup
cat << EOF

To track the status, you can start another console with appropriate KUBECONFIG
Then run:
    watch -n 5 kubectl -n trusted-identity get all
waiting 15s for the cleanup to complete...
EOF
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
  oc delete scc $SCCHOST --ignore-not-found=true
  oc delete scc $SCCPOD --ignore-not-found=true
  oc delete sa $SANAME --ignore-not-found=true
  oc delete group $GROUPNAME --ignore-not-found=true
  oc delete project $PROJECTNAME --ignore-not-found=true
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
local SETUP_FILE="tsi-node-setup.yaml"
# to list the chart values:
# helm inspect values charts/tsi-node-setup/
echo "executing: helm template ${TSI_ROOT}/charts/tsi-node-setup-${TSI_VERSION}.tgz"
helm template ${TSI_ROOT}/charts/tsi-node-setup-${TSI_VERSION}.tgz --name tsi-setup \
--set reset.all=false --set reset.x5c=true \
--set cluster.name=$CLUSTER_NAME --set cluster.region=$REGION > ${SETUP_FILE}
oc apply -f ${SETUP_FILE}
rm ${SETUP_FILE}
}

executeInstall-1() {
local INSTALL_FILE="tsi-install-1.yaml"
# to list the chart values:
# helm inspect values charts/ti-key-release-1/
echo "executing: helm template ${TSI_ROOT}/charts/ti-key-release-1-${TSI_VERSION}.tgz"
helm template ${TSI_ROOT}/charts/ti-key-release-1-${TSI_VERSION}.tgz --name tsi-1 --set vaultAddress=$VAULT_ADDR \
--set cluster.name=$CLUSTER_NAME --set cluster.region=$REGION --set runSidecar=$RUN_SIDECAR > ${INSTALL_FILE}
oc apply -f ${INSTALL_FILE}
# add the `ti-install-sa` to admin group
oc policy add-role-to-user cluster-admin system:serviceaccount:trusted-identity:ti-install-sa
rm ${INSTALL_FILE}
}

executeInstall-2() {
local INSTALL_FILE="tsi-install-2.yaml"
local HELM_REL_2="temp-release-2"
mkdir ${HELM_REL_2}
tar -xvzf ${TSI_ROOT}/charts/ti-key-release-2-${TSI_VERSION}.tgz -C ${HELM_REL_2}
# since we are not using nested helm charts, and set-1 is already executed,
# remove it from the relese-2, when using direct charts:
rm -rf ${HELM_REL_2}/ti-key-release-2/charts/ti-key-release-1*
rm ${HELM_REL_2}/ti-key-release-2/requirements.*

# to list the chart values:
# helm inspect values charts/ti-key-release-2/
helm template ${HELM_REL_2}/ti-key-release-2/ --name tsi-2 \
--set ti-key-release-1.vaultAddress=$VAULT_ADDR \
--set ti-key-release-1.cluster.name=$CLUSTER_NAME \
--set ti-key-release-1.cluster.region=$REGION \
--set ti-key-release-1.runSidecar=$RUN_SIDECAR \
--set jssService.type=$JSS_TYPE > ${INSTALL_FILE}

oc apply -f ${INSTALL_FILE}
rm -rf ${HELM_REL_2}
rm ${INSTALL_FILE}
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
echo "Wait for all Completed and Running"
read -n 1 -s -r -p 'Press any key to continue'
executeInstall-2
cat << EOF

Wait for all Running or Completed
*** One time initial bootstrapping setup required ***
For complete setup description please visit:
  https://github.com/IBM/trusted-service-identity/blob/master/examples/vault/README.md#register-jwt-signing-service-jss-with-vault

This process assumes Vault is already setup at another location as described:
  https://github.com/IBM/trusted-service-identity#setup-vault"

1. test the connection to Vault:
     export VAULT_ADDR="$VAULT_ADDR"
EOF
echo '     curl $VAULT_ADDR'
cat << EOF
   expected result: <a href=\"/ui/\">Temporary Redirect</a>
2. obtain the ROOT_TOKEN from the cluster with a running Vault instance and export it:
   (see https://github.com/IBM/trusted-service-identity/blob/master/examples/vault/README.md#vault-setup-as-vault-admin)
EOF
echo '     export ROOT_TOKEN=$(kubectl -n tsi-vault logs $(kubectl -n tsi-vault get po | grep tsi-vault-|'" awk '{" 'print $1}' "') | grep Root | cut -d' ' -f3);" ' echo "export ROOT_TOKEN=$ROOT_TOKEN"'
cat << EOF
3. setup shortcut alias:
     alias kk="kubectl -n trusted-identity"
4. test whether CSRs can be retrieved:
EOF
echo '    kk exec -it $(kk get po | grep tsi-node-setup | awk '"'{print "'$1}'"' |  sed -n 1p ) -- sh -c 'curl"' $HOST_IP:5000/public/getCSR'"'"

cat << EOF
5. execute cluster registration with Vault:
     examples/vault/demo.register-JSS.sh
6. the setup containers can be removed now:
     kk delete ds tsi-setup-tsi-node-setup
     kk delete sa tsi-setup-admin-sa
     oc delete scc $SCCHOST

Now you can test it by creating a new space and running a sample pod:
    kubectl create ns $APP_NS
Execute the script that extracts the secrets from the sample pod file:
    examples/vault/demo.secret-maker.sh -f examples/myubuntu.yaml  -n test > load_secrets_myubuntu.sh
Update the load_secrets_myubuntu.sh script with the actual password values, then execute it:
    sh load_secrets_myubuntu.sh
Now create the sample pod:
    kubectl create -f examples/myubuntu.yaml -n $APP_NS
Once running, execute:
EOF
echo "  kubectl -n $APP_NS"' exec -it $(kubectl -n test get pods | grep myubuntu | awk '"'{print "'$1}'"') -- cat /tsi-secrets/mysecret2"
echo "********* END ********"
