#!/bin/bash
TOKEN_SERVICE=${TOKEN_SERVICE:-"https://172.16.100.15:8444"}
VER_SERVICE=${VER_SERVICE:-"https://172.16.100.15:8443"}
VER_SERV_USERNAME=${VER_SERV_USERNAME:-"admin"}
VER_SERV_PASSWD=${VER_SERV_PASSWD:-"password"}
NODEHOSTNAME=${NODEHOSTNAME:-"worker5.test.ocp.nccoe.lab"}

cleanup()
{
  rm -rf ${TEMPDIR}
}

## create help menu:
helpme()
{
  cat <<HELPMEHELPME

Syntax: ${0} <REGION> <CLUSTER_NAME>

Where:
  REGION - name of the region (e.g. eu-de)
  CLUSTER_NAME - name of the Kubernetes cluster (e.g. my-cluster)
HELPMEHELPME
}

# validate the arguments
if [[ "$1" == "-?" || "$1" == "-h" || "$1" == "--help" ]] ; then
  helpme
  exit 0
elif
  [[ "$2" == "" ]]; then
    echo "Either REGION or CLUSTER_NAME not provided"
    helpme
    exit 1
else
  CLUSTER_REGION=$1
  CLUSTER_NAME=$2
fi

TEMPDIR=$(mktemp -d)
TOKEN_FILE=${TEMPDIR}/token

# get a token:
SC=$(curl -k --location --max-time 5 -s -w "%{http_code}" -o $TOKEN_FILE --request POST "${TOKEN_SERVICE}/aas/token" \
 --header 'Content-Type: application/json' \
 --data-raw '{ "username": "'${VER_SERV_USERNAME}'", "password": "'${VER_SERV_PASSWD}'" }')

if [ "$?" == "0" ] && [ "$SC" == "200" ] && [ -s "${TOKEN_FILE}" ]; then
  echo "Auth token received"
else
  echo "Error obtaining a token from Verfication Service: $SC"
  cleanup
  exit 1
fi

# get hardware uuid:
HOSTS_FILE=${TEMPDIR}/hosts
#HOSTS=$(curl -k --location --request GET 'https://172.16.100.15:8443/mtwilson/v2/hosts?nameEqualTo=worker5.test.ocp.nccoe.lab' \
SC=$(curl -k --location --max-time 5 -s -w "%{http_code}" -o $HOSTS_FILE --request GET "${VER_SERVICE}/mtwilson/v2/hosts?nameEqualTo=$NODEHOSTNAME" \
--header 'Content-Type: application/json' \
--header 'Accept: application/json' \
--header "Authorization: Bearer $(cat ${TOKEN_FILE})")

if [ "$?" == "0" ] && [ "$SC" == "200" ] && [ -s "${HOSTS_FILE}" ]; then
  echo "Host info for $NODEHOSTNAME received"
else
  echo "Error obtaining host information for $NODEHOSTNAME from Verfication Service: $SC"
  echo "Host info in ${HOSTS_FILE}: $(cat ${HOSTS_FILE})"
  cleanup
  exit 1
fi

HW_UUID=$(cat $HOSTS_FILE | jq -r '.hosts[].hardware_uuid')
RT=$?
if [ "$RT" == "0" ] && [ "${HW_UUID}" != "" ]; then
  echo "Hardware UUID: ${HW_UUID}"
else
  echo "Error parsing the $HOSTS_FILE: $(cat ${HOSTS_FILE})"
  echo "Hardware UUID: ${HW_UUID}"
  cleanup
  exit 1
fi

# create the hardware tag
HD_TAG_RESP=${TEMPDIR}/hd_tag_resp
SC=$(curl -k --location --max-time 5 -s -w "%{http_code}" -o ${HD_TAG_RESP} --request POST ${VER_SERVICE}/mtwilson/v2/tag-certificates \
--header 'Content-Type: application/json' \
--header 'Accept: application/json' \
--header "Authorization: Bearer $(cat ${TOKEN_FILE})" \
--data '{
  "hardware_uuid": "'"${HW_UUID}"'",
     "selection_content": [ {
         "name": "region",
         "value": "'"${CLUSTER_REGION}"'"
        }, {
         "name": "cluster-name",
         "value": "'"${CLUSTER_NAME}"'"
      }]
    }')

if [ "$?" == "0" ] && [ "$SC" == "200" ] && [ -s "${HD_TAG_RESP}" ]; then
  echo "Tag created for HW: ${HW_UUID} "
else
  echo "Error creating HW tag: $SC"
  echo "Tag response in ${HD_TAG_RESP}: $(cat ${HD_TAG_RESP})"
  cleanup
  exit 1
fi

CERT_ID=$(cat $HD_TAG_RESP | jq -r '.id')
RT=$?
if [ "$RT" == "0" ]; then
  echo "Cert id: ${CERT_ID}"
else
  echo "Error parsing the $HD_TAG_RESP: $CERT_ID"
  cleanup
  exit 1
fi

# deploy the tag cert
DEPLOY_RESP=${TEMPDIR}/deploy_resp
SC=$(curl -k --location --max-time 5 -s -w "%{http_code}" -o ${DEPLOY_RESP} --request POST ${VER_SERVICE}/mtwilson/v2/rpc/deploy-tag-certificate \
--header 'Content-Type: application/json' \
--header 'Accept: application/json' \
--header "Authorization: Bearer $(cat ${TOKEN_FILE})" \
--data '{"certificate_id": "'"${CERT_ID}"'"}')

if [ "$?" == "0" ] && [ "$SC" == "200" ] && [ -s "${DEPLOY_RESP}" ]; then
  echo "Tag successfully deployed"
else
  echo "Error deploying the tag CERT_ID: $SC"
  cho "Response in ${DEPLOY_RESP}: $(cat ${DEPLOY_RESP})"
  cleanup
  exit 1
fi

# get the SAML report with the Asset Tag:
SAML_JSON=${TEMPDIR}/SAML.json
SC=$(curl -k --location --max-time 5 -s -w "%{http_code}" -o ${SAML_JSON} --request POST ${VER_SERVICE}/mtwilson/v2/reports \
--header 'Content-Type: application/json' \
--header 'Accept: application/json' \
--header "Authorization: Bearer $(cat ${TOKEN_FILE})" \
--data '{"host_name": "'"${NODEHOSTNAME}"'"}')

if [ "$?" == "0" ] && [ "$SC" == "200" ] && [ -s "${SAML_JSON}" ]; then
  echo "SAML Report received"
else
  echo "Error receiving the SAML report: $SC"
  echo "Response in ${SAML_JSON}: $(cat ${SAML_JSON})"
  cleanup
  exit 1
fi

# parse the SAML report
# sample asset tag format:
# {
#   "trust": true,
#   "rules": [
#     {
#       "rule": {
#         "rule_name": "com.intel.mtwilson.core.verifier.policy.rule.AssetTagMatches",
#         "expected_tag": "16jgouItczhYB3yw8asDcp+h5X6y3uCO3LulNxrA5UpPGuzzWZMHjtO2Xg6RqwII",
#         "markers": [
#           "ASSET_TAG"
#         ],
#         "tags": {
#           "clustername": "clu2",
#           "region": "reg2"
#         }
#       },
ASSET_TAG=$(cat ${SAML_JSON} | jq -r '.trust_information.flavors_trust."ASSET_TAG".rules[] | select(.rule.rule_name == "com.intel.mtwilson.core.verifier.policy.rule.AssetTagMatches").rule.tags')
echo "ASSET_TAG: ${ASSET_TAG}"

ASSET_TAG_TRUST=$(cat ${SAML_JSON} | jq -r '.trust_information.flavors_trust."ASSET_TAG".trust')
echo "ASSET_TAG trust: ${ASSET_TAG_TRUST}"

cleanup
