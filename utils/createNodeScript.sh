#!/bin/bash
function usage {
    echo "$0 [node] [key-directory]"
    echo "where "
    echo " node - name of the node to create keys"
    echo " key-directory - directory with intermediate key, '../x509' default (optional)"
    exit 1
}
[[ -z $1 ]] && usage
NODE=$1
if [[ "$2" != "" ]] ; then
  KEYS="$2"
else
  KEYS="../x509"
fi

SCRIPTS="scripts"
mkdir -p ${SCRIPTS}
FILE=${SCRIPTS}/${NODE}.sh
TEMP_DIR="/tmp/ca"
TARGET_DIR="/target/run/spire/x509"

echo "#!/bin/bash" > ${FILE}
chmod 755 ${FILE}

echo "mkdir -p ${TEMP_DIR}" >> ${FILE}
echo "cd ${TEMP_DIR}" >> ${FILE}
echo "mkdir certs crl newcerts private" >> ${FILE}
echo "chmod 700 private" >> ${FILE}
echo "touch index.txt" >> ${FILE}
echo "echo 1000 > serial" >> ${FILE}
echo "cd -" >> ${FILE}

echo "cat > ${TEMP_DIR}/intermediate.cert.pem <<EOF" >> ${FILE}
if [ -f ${KEYS}/intermediate.cert.pem ]; then
  cat ${KEYS}/intermediate.cert.pem >> ${FILE}
  echo "EOF" >> ${FILE}
  echo " " >> ${FILE}
else
  echo "Error! Missing file ${KEYS}/intermediate.cert.pem"
  exit 1
fi

if [ -f ${KEYS}/intermediate.key.pem ]; then
  echo "cat > ${TEMP_DIR}/intermediate.key.pem <<EOF" >> ${FILE}
  cat ${KEYS}/intermediate.key.pem >> ${FILE}
  echo "EOF" >> ${FILE}
  echo " " >> ${FILE}
else
  echo "Error! Missing file ${KEYS}/intermediate.key.pem"
  exit 1
fi

echo "cat > ${TEMP_DIR}/intermediate-openssl.cnf <<EOF" >> ${FILE}
cat conf/intermediate-config.txt >> ${FILE}
echo "EOF" >> ${FILE}
echo " " >> ${FILE}

echo "openssl genrsa -out ${TEMP_DIR}/node.key.pem 2048" >> ${FILE}
echo "chmod 400 ${TEMP_DIR}/node.key.pem" >> ${FILE}

echo 'SUBJ="/C=US/ST=CA/O=MyOrg, Inc./CN='"$NODE"'"' >> ${FILE}

echo "openssl req -new -sha256 -key ${TEMP_DIR}/node.key.pem \\" >> ${FILE}
echo ' -subj "${SUBJ}"'" -out ${TEMP_DIR}/node.csr \\" >> ${FILE}
echo " -config ${TEMP_DIR}/intermediate-openssl.cnf 2>/dev/null" >> ${FILE}

echo "openssl ca -batch -config ${TEMP_DIR}/intermediate-openssl.cnf \\" >> ${FILE}
echo "    -extensions server_cert -days 375 -notext -md sha256 \\" >> ${FILE}
echo "    -in ${TEMP_DIR}/node.csr \\" >> ${FILE}
echo "    -out ${TEMP_DIR}/node.cert.pem 2>/dev/null" >> ${FILE}
echo "chmod 444 ${TEMP_DIR}/node.cert.pem" >> ${FILE}

echo "" >> ${FILE}
echo "# cleanup:" >> ${FILE}
echo "mkdir -p ${TARGET_DIR}" >> ${FILE}
echo "cat ${TEMP_DIR}/node.cert.pem \\" >> ${FILE}
echo "   ${TEMP_DIR}/intermediate.cert.pem > ${TARGET_DIR}/node-bundle.cert.pem" >> ${FILE}
echo "mv ${TEMP_DIR}/node.key.pem ${TARGET_DIR}/" >> ${FILE}
echo "rm -rf ${TEMP_DIR}/" >> ${FILE}
echo "rm -rf $SCRIPTS/" >> ${FILE}
echo "" >> ${FILE}
