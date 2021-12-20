#!/bin/bash

## create help menu:
helpme()
{
  cat <<HELPMEHELPME
This script returns cluster information

syntax:
   $0 [cluster-info.yaml]
where:
      [cluster-info.yaml] - cluster info, otherwise defaults to '/tmp/clusterinfo'
HELPMEHELPME
}

# validate the input arguments
if [[ "$1" == "-?" || "$1" == "-h" || "$1" == "--help" ]] ; then
    helpme
    exit 1
fi

if [[ "$1" == "" ]] ; then
  CLUSTER_YAML="/tmp/clusterinfo"
else
  CLUSTER_YAML="$1"
fi


### Get Cluter Information

# extract cluster and region info from provided data
CLYM1="/tmp/cl1.$$"
cat ${CLUSTER_YAML} > ${CLYM1}
CLJS1=$(yq r -j ${CLYM1} |jq -r '.data."cluster-config.json"')
rm "${CLYM1}"
CLUSTER=$(echo "$CLJS1" | jq -r '.name')
# DC=$(echo "$CLJS1" | jq -r '.datacenter')

# Confirmed with Armada team that CRN format should stay consistent for a while
# CRN format example:
# crn:v1:bluemix:public:containers-kubernetes:eu-de:586283a9abda5102d46e1b94b923a6c5:5f4306a2738d4cdd89ff067c9481555e
REGION=$(echo "$CLJS1" | jq -r '."crn"' | cut -d":" -f6)
echo "export CLUSTER_NAME=$CLUSTER"
echo "export REGION=$REGION"
# echo "export DATA_CENTER=$DC"
