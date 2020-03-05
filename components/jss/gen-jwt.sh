#!/usr/bin/env bash

# this script is use for debugging. It's not called by any of the components directly
# assuming 'private.key' and 'x5c' files exist, here is the format to test it:
#
#     /usr/local/bin/gen-jwt.sh -sub test@test.com -claims "name:tt|cluster-name:EUcluster|cluster-region:eu-de|images:trustedseriviceidentity/myubuntu@sha256:5b224e11f0,ubuntu:latest"


DIR="$(dirname "$0")"
STATEDIR=${STATEDIR:-/host/tsi-secure}
mkdir -p ${STATEDIR}

PRIV_KEY=${STATEDIR}/private.key
if ! [ -f ${PRIV_KEY} ]; then
  echo "${PRIV_KEY} is missing! Abort!"
  exit 1
fi

gen-jwt.py "${PRIV_KEY}" $@
