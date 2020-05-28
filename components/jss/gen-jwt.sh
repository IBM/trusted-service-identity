#!/usr/bin/env bash

# This script is used for debugging and manually generating JWT tokens.
#  It's not called by any of the components directly
#  assuming 'private.key' and 'x5c' files exist, here is the format to test it:
#
#     /usr/local/bin/gen-jwt.sh -sub test@test.com --claims="pod:myubuntu-6756d665bc-gc25f|namespace:test|images-names:ubuntu@sha256:250cc6f3f3ffc5cdaa9d8f4946ac79821aafb4d3afc93928f0de9336eba21aa4|images:30beed0665d9cb4df616cca84ef2c06d2323e02869fcca8bbfbf0d8c5a3987cc|cluster-name:my-cluster-name|region:eu-de|machineid=fbafad4e9df3498f85a555914e241539"
#
#   If your claims don't match the x5c, you might need to comment out in gen-jwt.py:
#    line 130   # payload = check_payload(payload, cc)

# TJW expires Jan 2052
export TTL_SEC=999999999

DIR="$(dirname "$0")"
STATEDIR=${STATEDIR:-/host/tsi-secure}
mkdir -p ${STATEDIR}

PRIV_KEY=${STATEDIR}/private.key
if ! [ -f ${PRIV_KEY} ]; then
  echo "${PRIV_KEY} is missing! Abort!"
  exit 1
fi

gen-jwt.py "${PRIV_KEY}" $@
