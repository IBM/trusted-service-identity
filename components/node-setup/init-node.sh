#!/bin/bash

# gather all the environemt variables and global parameters
# DIR="$(dirname "$0")"
RESETALL=${RESETALL:-"false"}
RESETX5C=${RESETX5C:-"true"}
PRIVATEDIR=${PRIVATEDIR:-/host/tsi-secure}
AUDIT_LOG=/host/logs/tsi-audit.log
PRIV_KEY=${PRIVATEDIR}/private.key
SERV_CSR=${PRIVATEDIR}/server.csr
X5C=${PRIVATEDIR}/x5c
SSLCONF=${PRIVATEDIR}/openssl.cnf

# a handy function to format the audit log
logme() {
echo "$1"
now=$(date +"%Y-%m-%d.%H:%M:%S")
echo "$now,$1" >> ${AUDIT_LOG}
}

# this function ends the operation and waits forever, so the container is not
# recreated
end() {
  # end of the audit log
  logme "end of audit record. Waiting forever now..."

  # keep the pod running
  tail -f /dev/null
}

# output some info about the pod processing these operations
logme "pod $HOSTNAME connected to host $(cat /host/etc/hostname) machineid: $(cat /host/etc/machine-id)"

# reset the private key and all the other secure stuff
if [ "$RESETALL" == "true" ]; then
  # TODO maybe we should hardcode the location. Othewise someone could do
  # a lot of damage to the host if passes wrong directory nama as a env. var
  rm -rf "${PRIVATEDIR}"
  #rm ${PRIV_KEY} ${SERV_CSR}
  logme "full reset performed"
fi

# openssl.cnf contains cluster idenity information and must be always created
# even if private keys are not created (e.g. to be used by VTPM2)
if [ "$CLUSTER_REGION" == "" ] || [ "$CLUSTER_NAME" == "" ]; then
  logme "Env. variables CLUSTER_REGION and CLUSTER_NAME must be set. Terminating..."
  end
else
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
# a "key:value" pair. For example:
# URI.3 = TSI:datacenter:fra02
EOF
fi

# reset the private key and all the other secure stuff
if [ "$RESETX5C" == "true" ]; then
  rm "${X5C}"
  logme "x5c file reset performed"
fi


if ! [ -d "${PRIVATEDIR}" ]; then
  mkdir -p "${PRIVATEDIR}"
  logme "directory ${PRIVATEDIR} created"
fi

# create a private key
if [ "$RESETALL" == "true" ]; then
  if ! [ -f "${PRIV_KEY}" ]; then
      openssl genrsa -out "${PRIV_KEY}" 2048
      openssl req -new -sha256 -key "${PRIV_KEY}" -out "${SERV_CSR}" -subj "/CN=jss-jwt-server" -reqexts v3_req -config <(cat /etc/ssl/openssl.cnf ${SSLCONF})
      logme "private key ${PRIV_KEY} and ${SERV_CSR} created"
      logme "for cluster-name: $CLUSTER_NAME and region:$CLUSTER_REGION"
   else
     logme "private key ${PRIV_KEY} and ${SERV_CSR} already exist. Do nothing"
   fi
fi
end
