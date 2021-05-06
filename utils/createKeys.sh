#!/bin/bash
function usage {
    echo "$0 [key-directory] [cluster-name] [ingress]"
    exit 1
}
[[ -z $3 ]] && usage
KEYSDIR=$1
CERTNAME=$2
ING=$3

ROOTCA="$KEYSDIR/CA/rootCA"
if [[ ! -f "$ROOTCA.key" ]]; then
    echo "Root CA must be created first."
    echo "Create CA certs:"
    echo "   openssl genrsa -out $ROOTCA.key 4096"
    echo "   openssl req -x509 -subj \"/C=US/ST=CA/O=Acme, Inc./CN=example.com\" -new -nodes -key $ROOTCA.key -sha256 -days 1024 -out $ROOTCA.crt"
    echo # empty line
    exit 1
fi

echo "Generating certs..."

SUBJ="/C=US/ST=CA/O=MyOrg, Inc./CN=mydomain.com"
SANSTR="[SAN]\nsubjectAltName=DNS:*.${ING},DNS:example.com,DNS:www.example.com"

openssl genrsa -out ${KEYSDIR}/${CERTNAME}.key 2048 2>/dev/null
openssl req -new -sha256 -key ${KEYSDIR}/${CERTNAME}.key -subj "${SUBJ}" -out ${KEYSDIR}/${CERTNAME}.csr \
 -reqexts SAN -config <(cat /etc/ssl/openssl.cnf <(printf ${SANSTR})) 2>/dev/null
# openssl req -in ${KEYSDIR}/${CERTNAME}.csr -noout -text
openssl x509 -req -extensions SAN \
    -extfile <(cat /etc/ssl/openssl.cnf <(printf $SANSTR)) \
    -in ${KEYSDIR}/${CERTNAME}.csr -CA ${ROOTCA}.crt \
    -CAkey ${ROOTCA}.key -CAcreateserial -out ${KEYSDIR}/${CERTNAME}.crt -days 500 -sha256 2>/dev/null
# openssl x509 -in ${KEYSDIR}/${CERTNAME}.crt -text -noout
