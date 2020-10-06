#!/bin/bash

# gather all the environemt variables and global parameters
# DIR="$(dirname "$0")"
SHAREDDIR=${SHAREDDIR:-/tsi-jss}
ATTEST_TYPE="IsecL"
HOST_IP=${HOST_IP:-"hostIP-not-provided"}
SSLCONF=${SSLCONF:-${SHAREDDIR}/tsissl.cnf}
HOSTDIR=${HOSTDIR:-/host/tsi-secure}

# a handy function to format the audit log
logme() {
echo "$1"
now=$(date +"%Y-%m-%d.%H:%M:%S")
# echo "$now,$1" > /host/tsi-log
echo "$now,$1"
}

# this function ends the operation
end() {
  # end of the audit log
  logme "end of ${ATTEST_TYPE} attestion on ${HOSTNAME} for host ${HOST_IP}."
  # keep the pod running
  #tail -f /dev/null
}

# output some info about the pod processing these operations
logme "beginning of ${ATTEST_TYPE} attestion on ${HOSTNAME} for host ${HOST_IP}."

if ! [ -d "${SHAREDDIR}" ]; then
  logme "ERROR: directory ${SHAREDDIR} must be created"
  exit 1
fi

TEMPSSL="/tmp/openssl.cnf"
# get the TSI specific info from the attestation and make sure it's successfully created
/usr/local/bin/isecl-get-openssl-cnf.sh > ${TEMPSSL}
if [ "$?"=="0" ] && [ -s ${TEMPSSL} ]; then
 mv ${TEMPSSL} ${SSLCONF}
else
  logme "ERROR: ${ATTEST_TYPE} attestation failed"
  exit 1
fi

# VTPM2 server is using host socket to communicate with the TSI sidecar
# clean this up
if ! [ -d "${HOSTDIR}/sockets" ]; then
  MKDIR="mkdir -p ${HOSTDIR}/sockets"
  if $MKDIR; then
    logme "directory ${HOSTDIR}/sockets succesfully created"
  else
    logme "ERROR: directory ${HOSTDIR}/sockets could not be created"
    exit 1
  fi
else
  if [ -f "${HOSTDIR}/sockets/app.sock" ]; then
    RMDIR="rm ${HOSTDIR}/sockets/app.sock"
    if $RMDIR; then
      logme "${HOSTDIR}/sockets/app.sock succefully removed"
    else
      logme "ERROR: ${HOSTDIR}/sockets/app.sock could not be removed"
      exit 1
    fi
  fi
fi

end
