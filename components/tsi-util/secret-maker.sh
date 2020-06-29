#!/bin/bash

SECRET_VALUE='$SECRET_VALUE'

### Functions:

# Print the header:
header()
{
cat << EOF
#!/bin/bash

# **** Trusted Service Identity ****
# **** IBM Research ****************
# https://github.com/IBM/trusted-service-identity/
#
# This auto-generated script provides helpful tooling
# for injecting TSI secrets into Vault based on the input
# deployment file
#
# Assumptions:
#  1. Input file has properly defined annotations including
#    a. 'tsi.secrets'
#    b. 'admission.trusted.identity/inject: "true"'
#  2. Script is executed in the environment that has Vault client installed
#     (https://www.vaultproject.io/downloads)
#  3. Vault env. variables are set
#     export ROOT_TOKEN=
#     export VAULT_ADDR=(vault address in format http://vault.server:8200)

# Define values for the SECRET_VALUE(s)
# they must be in "key=value" format
# For more info see:
# https://github.com/IBM/trusted-service-identity/examples/vault/README.md#secrets
export SECRET_VALUE="secret=xxx"


EOF

# prevent expression expending by using a single quote:
echo 'vault login -no-print "${ROOT_TOKEN}"
RT=$?
if [ $RT -ne 0 ] ; then
   echo "ROOT_TOKEN is not set correctly"
   exit 1
fi'

}

## create help menu:
helpme()
{
  cat <<HELPMEHELPME
This script helps building TSI policies

syntax:
   $0 [cluster-info.yaml] [pod-info.yaml]
where:
      [cluster-info.yaml] - cluster info, otherwise defaults to '/tmp/clusterinfo'
      [pod-info.yaml] - pod info, otherwise defaults to '/tmp/podinfo'
HELPMEHELPME
}

# buildSecrets - build individual secret entries
buildSecrets()
{
  local SECNAME=$1
  local CONSTR=$2

  case $CONSTR in
      "region")
          echo "# using policy $CONSTR"
          echo "vault kv put secret/tsi-r/${REGION}/${SECNAME} ${SECRET_VALUE}"
          POLICIES+=('tsi-r')
          ;;
      "region,images")
          echo "# using policy $CONSTR"
          echo "vault kv put secret/tsi-ri/${REGION}/${IMGSHA}/${SECNAME} ${SECRET_VALUE}"
          POLICIES+=('tsi-ri')
          ;;
      "region,cluster-name,namespace")
          echo "# using policy $CONSTR"
          ROLE="tsi-role-rcn"
          VAULT_PATH="secret/tsi-rcn"
          echo "vault kv put secret/tsi-rcn/${REGION}/${CLUSTER}/${NS}/${SECNAME} ${SECRET_VALUE}"
          POLICIES+=('tsi-rcn')
          ;;
      "region,cluster-name,namespace,images")
          echo "# using policy $CONSTR"
          echo "vault kv put secret/tsi-rcni/${REGION}/${CLUSTER}/${NS}/${IMGSHA}/${SECNAME} ${SECRET_VALUE}"
          POLICIES+=('tsi-rcni')
          ;;
      *) echo "# ERROR: invalid constraints requested: ${CONSTR} for ${SECNAME}"
         ;;
  esac
}

#### End of functions

# validate the arguments
if [[ "$1" == "-?" || "$1" == "-h" || "$1" == "--help" ]] ; then
    helpme
    exit 1
fi

if [[ "$1" == "" ]] ; then
  CLUSTER_YAML="/tmp/clusterinfo"
else
  CLUSTER_YAML="$1"
fi

if [[ "$2" == "" ]] ; then
  POD_YAML="/tmp/podinfo"
else
  POD_YAML="$2"
fi

### Get Cluter Information

# extract cluster and region info from provided data
CLYM1="/tmp/cl1.$$"
cat ${CLUSTER_YAML} > ${CLYM1}
CLJS1=$(yq r -j ${CLYM1} |jq -r '.data."cluster-config.json"')
rm "${CLYM1}"
CLUSTER=$(echo "$CLJS1" | jq -r '.name')
DC=$(echo "$CLJS1" | jq -r '.datacenter')

# Confirmed with Armada team that CRN format should stay consistent for a while
# CRN format example:
# crn:v1:bluemix:public:containers-kubernetes:eu-de:586283a9abda5102d46e1b94b923a6c5:5f4306a2738d4cdd89ff067c9481555e
REGION=$(echo "$CLJS1" | jq -r '."crn"' | cut -d":" -f6)

# Get Pod information

# getting the secrets annotations require a bit more work
TMPTSI="/tmp/tsi.$$"
cat ${POD_YAML} > ${TMPTSI}.1

# get the kind of the deployment:
KIND=$(yq r -j ${TMPTSI}.1 |jq -r '.kind')

# get the attribute path based on kind:
case $KIND in
    "Deployment")
        TSI_INJECT='.spec.template.metadata.annotations."admission.trusted.identity/inject"'
        TSI_SECRETS='.spec.template.metadata.annotations."tsi.secrets"'
        TSI_IMG='.spec.template.spec.containers[0].image'
        ;;
    "DaemonSet")
        TSI_INJECT='.spec.template.metadata.annotations."admission.trusted.identity/inject"'
        TSI_SECRETS='.spec.template.metadata.annotations."tsi.secrets"'
        TSI_IMG='.spec.template.spec.containers[0].image'
        ;;
    "Pod")
        TSI_INJECT='.metadata.annotations."admission.trusted.identity/inject"'
        TSI_SECRETS='.metadata.annotations."tsi.secrets"'
        TSI_IMG='.spec.containers[0].image'
        ;;
    *) echo "# ERROR: Unsupported kind: ${KIND} in ${CLUSTER_YAML}"
       exit 1
       ;;
esac


yq r -j ${TMPTSI}.1 |jq -r "${TSI_SECRETS}" > ${TMPTSI}.2

DEPLOY=$(yq r -j ${TMPTSI}.1)
NS=$(echo $DEPLOY | jq -r '.metadata.namespace')

# TODO we need to add support for multiple images in one pod.
# Sort them alphabetically. Do the same algorithm in TSI
IMG=$(echo $DEPLOY | jq -r "${TSI_IMG}")

# Get the SHA-256 encoded image name.
# Encoder depends on the OS:
if [[ "$OSTYPE" == "linux-gnu" ]]; then
  # Linux
  IMGSHA=$(echo -n "$IMG" | sha256sum | awk '{print $1}')
elif [[ "$OSTYPE" == "darwin"* ]]; then
  # Mac OSX
  IMGSHA=$(echo -n "$IMG" | shasum -a 256 | awk '{print $1}')
else
  # Unknown.
  echo "ERROR: Cannot encode the image name. Unsupported platform"
  exit 1
fi


# validate if tsiEnabled is provided correctly
# tsiEnabled - convert to lowercase:
tsiEnabled=$(echo $DEPLOY | jq -r "${TSI_INJECT}" | awk '{print tolower($0)}')
if [[ "$tsiEnabled" == "true" || "$tsiEnabled" == "yes"  || "$tsiEnabled" == "on" || "$tsiEnabled" == "y" ]] ; then
  header
  echo "# Using kind: $KIND"
  echo "# TSI is enabled"
  echo "# Cluster: $CLUSTER DataCenter: $DC Region: $REGION"
  echo "# NS: $NS, IMG: $IMG, IMGSHA: $IMGSHA"
else
  echo "# ERROR: TSI must be enabled to continue! "
  echo "# Set 'admission.trusted.identity/inject' annotation to 'true'"
  exit 1
fi

JSON=$(yq r -j ${TMPTSI}.2)
rm ${TMPTSI}.1 ${TMPTSI}.2

POLICIES=()

for row in $(echo "${JSON}" | jq -c '.[]' ); do
  # for each requested secret parse its attributes
  SECNAME=$(echo "$row" | jq -r '."tsi.secret/name"')
  CONSTR=$(echo "$row" | jq -r '."tsi.secret/constraints"')
  LOCPATH=$(echo "$row" | jq -r '."tsi.secret/local-path"')

  # local-path must start with "tsi-secrets"
  if [[ ${LOCPATH} == "tsi-secrets" ]] || [[ ${LOCPATH} == "/tsi-secrets" ]] || [[ ${LOCPATH} == /tsi-secrets/* ]] || [[ ${LOCPATH} == tsi-secrets/* ]]; then

    # build the injection of secret:
    buildSecrets "$SECNAME" "$CONSTR"
  else
    echo "# ERROR: invalid local-path value: $LOCPATH"
  fi
done

# remove duplicated policies:
sorted_unique_ids=($(echo "${POLICIES[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
echo "# this $KIND uses the following policies/paths: "
echo "# ${sorted_unique_ids[@]}"
