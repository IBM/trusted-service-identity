#!/bin/bash

# gather all the environemt variables and global parameters
DIR="$(dirname "$0")"
RESET=${RESET:-"false"}
PRIVATEDIR=${PRIVATEDIR:-/host/tsi-secure}
AUDIT_LOG=/logs/tsi-audit.log
PRIV_KEY=${PRIVATEDIR}/private.key
SERV_CSR=${PRIVATEDIR}/server.csr

# a handy function to format the audit log
logme() {
echo $1
now=$(date +"%Y-%m-%d.%H:%M:%S")
echo "$now,$1" >> ${AUDIT_LOG}
}

# output some info about the pod processing these operations
logme "pod $HOSTNAME connected to host $(cat /host/etc/hostname) machineid: $(cat /host/etc/machine-id)"

# reset the private key and all the other secure stuff
if [ "$RESET" == "true" ]; then
  # TODO maybe we should hardcode the location. Othewise someone could do
  # a lot of damage to the host if passes wrong directory nama as a env. var
  rm -rf ${PRIVATEDIR}
  #rm ${PRIV_KEY} ${SERV_CSR}
  logme "reset performed"
fi

if ! [ -d ${PRIVATEDIR} ]; then
  mkdir -p ${PRIVATEDIR}
  logme "directory ${PRIVATEDIR} created"
fi


# create a private key
if ! [ -f ${PRIV_KEY} ]; then
 openssl genrsa -out ${PRIV_KEY} 2048
 openssl req -new -sha256 -key ${PRIV_KEY} -out ${SERV_CSR} -subj "/CN=jss-jwt-server"
 logme "private key ${PRIV_KEY} and ${SERV_CSR} created"
else
  logme "privte key ${PRIV_KEY} and ${SERV_CSR} already exist. Do nothing"
fi

# end of the audit log
logme "end of audit record"

# keep the pod running
tail -f /dev/null
