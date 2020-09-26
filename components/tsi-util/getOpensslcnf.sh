#!/bin/bash
TOKEN_SERVICE=${TOKEN_SERVICE:-"https://172.16.100.15:8444"}
VER_SERVICE=${VER_SERVICE:-"https://172.16.100.15:8443"}
VER_SERV_USERNAME=${VER_SERV_USERNAME:-"admin"}
VER_SERV_PASSWD=${VER_SERV_PASSWD:-"password"}
NODEHOSTNAME=${NODEHOSTNAME:-"worker5.test.ocp.nccoe.lab"}

TEMPDIR="/tmp/tsi.$$"

cleanup()
{
  rm -rf ${TEMPDIR}
  #echo "Cleanup executed"
}

## create help menu:
helpme()
{
  cat <<HELPMEHELPME

Syntax: ${0}

This script returns auto-generated openssl.cnf file that
is using ASSET_TAG key value pairs

HELPMEHELPME
}

# validate the arguments
if [[ "$1" == "-?" || "$1" == "-h" || "$1" == "--help" ]] ; then
  helpme
  exit 1
fi

mkdir -p ${TEMPDIR}
TOKEN_FILE=${TEMPDIR}/token

# get a token:
SC=$(curl -k --location --max-time 5 -s -w "%{http_code}" -o $TOKEN_FILE --request POST "${TOKEN_SERVICE}/aas/token" \
 --header 'Content-Type: application/json' \
 --data-raw '{ "username": "'${VER_SERV_USERNAME}'", "password": "'${VER_SERV_PASSWD}'" }')

if [ "$SC" != "200" ] || [ ! -s "${TOKEN_FILE}" ]; then
  echo "ERROR obtaining a token from Verfication Service: $SC"
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

if [ "$SC" != "200" ] || [ ! -s "${SAML_JSON}" ]; then
  echo "ERROR receiving the SAML report: $SC"
  echo "Response in ${SAML_JSON}: $(cat ${SAML_JSON})"
  cleanup
  exit 1
fi

# parse the SAML report
# First check if all the fields are marked as trusted
OVERALL=$(cat ${SAML_JSON} | jq -r '.trust_information.OVERALL')
if [ "${OVERALL}" != "true" ]; then
  echo "ERROR! SAML report OVERALL trust: ${OVERALL}"
  cleanup
  exit 1
fi

for k in $(jq -r '.trust_information.flavors_trust | keys | .[]' ${SAML_JSON}); do
  value=$(jq -r ".trust_information.flavors_trust.$k.trust " ${SAML_JSON})
  if [ "$value" != "true" ]; then
     echo "ERROR: Attestation failed: $k.trust=$value"
     cleanup
     exit 1
  fi
done


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

ASSET_TAG_TRUST=$(cat ${SAML_JSON} | jq -r '.trust_information.flavors_trust."ASSET_TAG".trust')
#echo "ASSET_TAG trust: ${ASSET_TAG_TRUST}"
if [ "$ASSET_TAG_TRUST" != "true" ]; then
   echo "ERROR: ASSET_TAG trust is $ASSET_TAG_TRUST"
   cleanup
   exit 1
fi

ASSET_TAG=$(cat ${SAML_JSON} | jq -r '.trust_information.flavors_trust."ASSET_TAG".rules[] | select(.rule.rule_name == "com.intel.mtwilson.core.verifier.policy.rule.AssetTagMatches").rule.tags')
#echo "ASSET_TAG: ${ASSET_TAG}"


# openssl.cnf contains cluster idenity information and must be always created
# even if private keys are not created (e.g. to be used by VTPM2)
SSLCONF=${TEMPDIR}/openssl.cnf

cat > ${SSLCONF} << EOF
# IBM Research - TSI
# this is an auto-generated openssl.cnf file
# using ASSET TAG

[req]
req_extensions = v3_req
distinguished_name	= req_distinguished_name

[ req_distinguished_name ]
countryName      = Country Name (2 letter code)
countryName_min  = 2
countryName_max  = 2
stateOrProvinceName = State or Province Name (full name)
localityName        = Locality Name (eg, city)
0.organizationName  = Organization Name (eg, company)
organizationalUnitName = Organizational Unit Name (eg, section)
commonName       = Common Name (eg, fully qualified host name)
commonName_max   = 64
emailAddress     = Email Address
emailAddress_max = 64

[v3_req]
subjectAltName= @alt_names

# To assert additional claims about this intermediate CA
# add new lines in the following format:
# URI.x = TSI:<claim>
# where x is a next sequencial number and claim is
# a key:value pair. For example:
# URI.3 = TSI:datacenter:fra02
[alt_names]
EOF

i=1
for k in $(jq -r '. | keys |.[]' <<< $ASSET_TAG); do
   val=$(jq -r ".\"$k\"" <<< $ASSET_TAG)
   echo "URI.$i = TSI:$k:$val" >> ${SSLCONF};
   ((i=i+1))
done
echo "URI.$i = TSI:attestion-trusted:true" >> ${SSLCONF};

cat ${SSLCONF}
cleanup
