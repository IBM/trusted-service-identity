
if ! [ -f ${STATEDIR} ]; then
	# throw error and return
  echo "ERROR: STATEDIR never set!!"
fi

PRIV_KEY=${STATEDIR}/private.key
if ! [ -f ${PRIV_KEY} ]; then
 openssl genrsa -out ${PRIV_KEY} 2048
 openssl req -new -sha256 -key ${PRIV_KEY} -out ${STATEDIR}/server.csr -subj "/CN=jss-jwt-server"
fi
