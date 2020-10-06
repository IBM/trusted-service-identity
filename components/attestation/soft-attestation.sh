#!/bin/bash -x

# gather all the environemt variables and global parameters
# DIR="$(dirname "$0")"
SHAREDDIR=${SHAREDDIR:-/tsi-jss}
ATTEST_TYPE="soft"
HOST_IP=${HOST_IP:-"hostIP-not-provided"}
SSLCONF=${SSLCONF:-${SHAREDDIR}/tsissl.cnf}
HOSTDIR=${HOSTDIR:-/host}

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


# openssl.cnf contains cluster idenity information and must be always created
# even if private keys are not created (e.g. to be used by VTPM2)
if [ "$CLUSTER_REGION" == "" ] || [ "$CLUSTER_NAME" == "" ]; then
  logme "Env. variables CLUSTER_REGION and CLUSTER_NAME must be set. Terminating..."
  end
else
  # logme "**** ${SSLCONF}"
  cat > ${SSLCONF} << EOF
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

[alt_names]
URI.1 = TSI:cluster-name:$CLUSTER_NAME
URI.2 = TSI:region:$CLUSTER_REGION
# To assert additional claims about this intermediate CA
# add new lines in the following format:
# URI.x = TSI:<claim>
# where x is a next sequencial number and claim is
# a key:value pair. For example:
# URI.3 = TSI:datacenter:fra02
EOF
fi

# VTPM2 server is using host socket to communicate with the TSI sidecar
# clean this up
if ! [ -d "${HOSTDIR}/sockets" ]; then
  MKDIR="mkdir -p ${HOSTDIR}/sockets"
  # if [ "$?" == "0" ]; then
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
