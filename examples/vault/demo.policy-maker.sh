#!/bin/bash

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
#  1. File has properly defined annotations including
#    a. 'tsi.secrets'
#    b. 'admission.trusted.identity/inject: "true"'
#  2.


# Define values for the SECRET_VALUE(s)
# they must be in "key=value" format
# For more info see:
# https://github.com/IBM/trusted-service-identity/examples/vault/README.md#secrets
export SECRET_VALUE="secret="

# To access vault, obtain the Vault Client from (...)
#  and define ROOT_TOKEN and VAULT_ADDR env. variables:
#
# export ROOT_TOKEN=
# export VAULT_ADDR=(vault address in format http://vault.server:8200)
#
EOF

# prevent expression expending by using a single quote:
echo 'vault login -no-print "${ROOT_TOKEN}"
RT=$?
if [ $RT -ne 0 ] ; then
   echo "ROOT_TOKEN is not set correctly"
   exit 1
fi'

}

SECRET_VALUE='$SECRET_VALUE'


## create help menu:
helpme()
{
  cat <<HELPMEHELPME
This script helps building TSI policies

syntax:
   $0 -f [deployment-file-name] -n namespace
where:
      [deployment-file-name] name of the file to inspect

HELPMEHELPME
}

# {
#   "cluster-name": "my-cluster-name",
#   "region": "eu-de",
#   "exp": 1590494405,
#   "iat": 1590494345,
#   "images": "30beed0665d9cb4df616cca84ef2c06d2323e02869fcca8bbfbf0d8c5a3987cc",
#   "images-names": "ubuntu@sha256:250cc6f3f3ffc5cdaa9d8f4946ac79821aafb4d3afc93928f0de9336eba21aa4",
#   "iss": "wsched@us.ibm.com",
#   "machineid": "b46e165c32d342d9896d9eeb43c4d5dd",
#   "namespace": "test",
#   "pod": "myubuntu-6756d665bc-cb49l",
#   "sub": "wsched@us.ibm.com"
# }
# root@myubuntu-6756d665bc-cb49l:/# cat jwt/token | cut -d"." -f2 |base64 --decode |jq -r '.images'
# 30beed0665d9cb4df616cca84ef2c06d2323e02869fcca8bbfbf0d8c5a3987cc

# validate the arguments
if [[ "$1" == "-?" || "$1" == "-h" || "$1" == "--help" || "$2" == "" ]] ; then
    helpme
    exit 1
fi

NS="default"

POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -f|--file)
    FILE="$2"
    shift # past argument
    shift # past value
    ;;
    -n|--namespace)
    NS="$2"
    shift # past argument
    shift # past value
    ;;
    --default)
    DEFAULT=YES
    shift # past argument
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done

# extract cluster and region info from K8s
CLYM1="/tmp/cl1.$$"
kubectl get cm -n kube-system cluster-info -o yaml > ${CLYM1}
CLJS1=$(yq r -j ${CLYM1} |jq -r '.data."cluster-config.json"')
rm "${CLYM1}"
#echo $CLJS1
CLUSTER=$(echo "$CLJS1" | jq -r '.name')
DC=$(echo "$CLJS1" | jq -r '.datacenter')

# Confirmed with Armada team that CRN format should stay consistent for a while
# CRN format example:
# crn:v1:bluemix:public:containers-kubernetes:eu-de:586283a9abda5102d46e1b94b923a6c5:5f4306a2738d4cdd89ff067c9481555e
REGION=$(echo "$CLJS1" | jq -r '."crn"' | cut -d":" -f6)

# extract the deployment information from the deployment file
DEPLOY=$(kubectl create -f ${FILE} -n ${NS} --dry-run=true -ojson |jq)

NS=$(echo $DEPLOY | jq -r '.metadata.namespace')
# TODO we need to add support for multiple images in one pod.
# Sort them alphabetically. Do the same algorithm in TSI
IMG=$(echo $DEPLOY | jq -r '.spec.template.spec.containers[0].image')

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
tsiEnabled=$(echo $DEPLOY | jq -r '.spec.template.metadata.annotations."admission.trusted.identity/inject"' | awk '{print tolower($0)}')
if [[ "$tsiEnabled" == "true" || "$tsiEnabled" == "yes"  || "$tsiEnabled" == "on" || "$tsiEnabled" == "y" ]] ; then
  header
  echo "# TSI is enabled"
else
  echo "# ERROR: TSI must be enabled to continue! "
  echo "# Set 'admission.trusted.identity/inject' annotation to 'true'"
  exit 1
fi

echo "# Cluster: $CLUSTER DataCenter: $DC Region: $REGION"

#secrets=$(echo $DEPLOY | jq -r '.spec.template.metadata.annotations."tsi.secrets"')
#echo $DEPLOY | jq -r '.spec.template.metadata.annotations'
echo "# NS=$NS, IMG: $IMG, IMGSHA: $IMGSHA"
#echo "$secrets"

POLICIES=()


buildSecrets()
{
  local SECNAME=$1
  local CONSTR=$2

  # Then parse the response to get other attributes associated
  # with this token.
  # Doublequotes required when the key name contains '-'
  # REGION=$(echo $RESP | jq -r '.auth.metadata."region"')
  # CLUSTER=$(echo $RESP | jq -r '.auth.metadata."cluster-name"')
  # IMGSHA=$(echo $RESP | jq -r '.auth.metadata.images')
  # NS=$(echo $RESP | jq -r '.auth.metadata.namespace')
  #
  # echo "Getting $SECNAME from Vault $VAULT_PATH and output to $LOCPATH"
  # if [ "$VAULT_PATH" == "secret/tsi-rcni" ]; then
  #   CMD="vault kv get -format=json ${VAULT_PATH}/${REGION}/${CLUSTER}/${NS}/${IMGSHA}/${SECNAME}"
  # elif [ "$VAULT_PATH" == "secret/tsi-r" ]; then
  #   CMD="vault kv get -format=json ${VAULT_PATH}/${REGION}/${SECNAME}"
  # elif [ "$VAULT_PATH" == "secret/tsi-rcn" ]; then
  #   CMD="vault kv get -format=json ${VAULT_PATH}/${REGION}/${CLUSTER}/${NS}/${SECNAME}"
  # else
  #   echo "Unknown Vault path value!"
  #   rm -rf "${LOCPATHDIR}/${LOCPATH}/${SECNAME}"
  #   return 1
  # fi

  case $CONSTR in
      "region")
          echo "# using policy $CONSTR"
          # PL="tsi-ri"
          # REGION=`echo $CLAIMS |jq -r '."region"'`
          # IMG=`echo $CLAIMS |jq -r '."images"'`
          echo "vault kv put secret/tsi-r/${REGION}/${SECNAME} ${SECRET_VALUE}"
          POLICIES+=('tsi-r')
          ;;
      "region,images")
          echo "# using policy $CONSTR"
          # PL="tsi-r"
          # REGION=`echo $CLAIMS |jq -r '."region"'`
          # CLUSTER=`echo $CLAIMS |jq -r '."cluster-name"'`
          # IMG=`echo $CLAIMS |jq -r '."images"'`
          echo "vault kv put secret/tsi-ri/${REGION}/${IMGSHA}/${SECNAME} ${SECRET_VALUE}"
          POLICIES+=('tsi-ri')
          ;;
      "region,cluster-name,namespace")
          echo "# using policy $CONSTR"
          ROLE="tsi-role-rcn"
          VAULT_PATH="secret/tsi-rcn"
          # PL="tsi-r"
          # REGION=`echo $CLAIMS |jq -r '."region"'`
          # CLUSTER=`echo $CLAIMS |jq -r '."cluster-name"'`
          # IMG=`echo $CLAIMS |jq -r '."images"'`
          echo "vault kv put secret/tsi-rcn/${REGION}/${CLUSTER}/${NS}/${SECNAME} ${SECRET_VALUE}"
          POLICIES+=('tsi-rcn')
          ;;
      "region,cluster-name,namespace,images")
          echo "# using policy $CONSTR"
          # PL="tsi-rcni"
          # REGION=`echo $CLAIMS |jq -r '."region"'`
          # CLUSTER=`echo $CLAIMS |jq -r '."cluster-name"'`
          # NS=`echo $CLAIMS |jq -r '."namespace"'`
          # IMG=`echo $CLAIMS |jq -r '."images"'`
          echo "vault kv put secret/tsi-rcni/${REGION}/${CLUSTER}/${NS}/${IMGSHA}/${SECNAME} ${SECRET_VALUE}"
          POLICIES+=('tsi-rcni')
          ;;
      *) echo "# ERROR: invalid constrains requested: ${CONSTR}"
         ;;
  esac

}

# getting the secrets annotations require a bit more work
TMPTSI="/tmp/tsi.$$"
kubectl create -f ${FILE} -n ${NS} --dry-run=true -oyaml > ${TMPTSI}.1
yq r -j ${TMPTSI}.1 |jq -r '.spec.template.metadata.annotations."tsi.secrets"' > ${TMPTSI}.2
#JSON1=$(yq r -j /tmp/tsi.1)
#echo $JSON1 | jq -r '.spec.template.metadata.annotations."tsi.secrets"' > /tmp/tsi.2
JSON=$(yq r -j ${TMPTSI}.2)
rm ${TMPTSI}.1 ${TMPTSI}.2

for row in $(echo "${JSON}" | jq -c '.[]' ); do
  # for each requested secret parse its attributes
  SECNAME=$(echo "$row" | jq -r '."tsi.secret/name"')
  CONSTR=$(echo "$row" | jq -r '."tsi.secret/constrains"')
  LOCPATH=$(echo "$row" | jq -r '."tsi.secret/local-path"')

  # local-path must start with "mysecrets"
  if [[ ${LOCPATH} == "mysecrets" ]] || [[ ${LOCPATH} == "/mysecrets" ]] || [[ ${LOCPATH} == /mysecrets/* ]] || [[ ${LOCPATH} == mysecrets/* ]]; then

    # build the injection of secret:
    buildSecrets "$SECNAME" "$CONSTR"
    RT=$?
    if [ "$RT" != "0" ]; then
      echo "Error building a secret SECNAME=${SECNAME}, CONSTR=${CONSTR}, LOCPATH=${LOCPATH}"
    fi

  else
    echo "# ERROR: invalid local-path value: $LOCPATH"
  fi



done

#echo "# ${POLICIES[@]}"
# remove duplicated policies:
sorted_unique_ids=($(echo "${POLICIES[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
echo "# this deployment uses the following policies/paths: "
echo "# ${sorted_unique_ids[@]}"
