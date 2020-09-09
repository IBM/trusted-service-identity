
SWTPM_SERVER_PORT=65426

export TPM_SERVER_NAME=localhost
export TPM_SERVER_TYPE=${TPM_SERVER_TYPE:-raw}
export TPM_INTERFACE_TYPE=${TPM_INTERFACE_TYPE:-socsim}
export TPM_COMMAND_PORT=${SWTPM_SERVER_PORT}
export TPM_DEVICE=${TPM_DEVICE:-/dev/tpm0}
export TPM_PERSISTENT_KEY_INDEX=${TPM_PERSISTENT_KEY_INDEX:-81230001}
export TPM_OWNER_PASSWORD_FORMAT=${TPM_OWNER_PASSWORD_FORMAT:-hex}

if [ -n "${TPM_OWNER_PASSWORD}" ] && [ "${TPM_OWNER_PASSWORD_FORMAT}" == "hex" ]; then
   TPM_OWNER_PASSWORD=$(echo -en "${TPM_OWNER_PASSWORD}" | sed -n 's/\([0-9a-f]\{2\}\)/\\x\1/pg')
fi

ORIG_TPM_DEVICE="${TPM_DEVICE}"
ORIG_TPM_INTERFACE_TYPE="${TPM_INTERFACE_TYPE}"

if [ "${TPM_INTERFACE_TYPE}" == "socsim" ]; then
	swtpm socket \
		--tpm2 \
		--tpmstate "dir=${STATEDIR}" \
		--flags not-need-init \
		--daemon \
		--server type=tcp,port=${TPM_COMMAND_PORT}
	sleep 1
	tssstartup -c || exit 1
	if [ -n "${VERBOSE}" ]; then
		echo "Started swtpm and initialized it" >&2
	fi
	if [ -n "${TPM_OWNER_PASSWORD}" ]; then
		# Adjust the owner password
		tsshierarchychangeauth -hi o -pwdn "$(echo -en "${TPM_OWNER_PASSWORD}")"
	fi
else
	if [ -n "${VERBOSE}" ]; then
		echo "Using hardware TPM at ${TPM_DEVICE}" >&2
	fi
	if [ ! -c "${TPM_DEVICE}" ]; then
		echo "TPM device ${TPM_DEVICE} is not available inside the container" >&2
	fi
	if [[ ${TPM_DEVICE} =~ ^/dev/tpmrm[0-9]+ ]]; then
		echo "Starting tpm_proxy" >&2
		# we have to use the proxy in this case
		/usr/local/bin/tpm_proxy --persisttpm \
			--port ${TPM_COMMAND_PORT} --device "${TPM_DEVICE}" &
		sleep 1
		unset TPM_DEVICE
		export TPM_INTERFACE_TYPE=socsim
		export TPM_SERVER_TYPE=raw
	fi
fi

TSIOPENSSLCNF="/host/tsi-secure/openssl.cnf"
if ! [ -f "${TSIOPENSSLCNF}" ]; then
	echo "Missing ${TSIOPENSSLCNF} file with node identity"
	exit 1
fi

TPMKEYFILE="${STATEDIR}/tpm.key"

if ! [ -f "${TPMKEYFILE}" ]; then
	# Check whether a key is already there at 'our' index
	tssreadpublic -ho "${TPM_PERSISTENT_KEY_INDEX}" -opem "${STATEDIR}/tpmpubkey.persist.pem" &>/dev/null
	if [ $? -ne 0 ]; then
		# need to create the key first
		OUTPUT=$(tsscreateprimary -hi o -st -rsa ${TPM_OWNER_PASSWORD:+-pwdp "$(echo -en "${TPM_OWNER_PASSWORD}")"}  \
			${VERBOSE+-v} 2>&1) || { echo "${OUTPUT}" ; exit 1 ; }
		HANDLE=$(echo "${OUTPUT}" | grep -E "^Handle" | gawk '{print $2}')
		echo "OUPUT=$OUTPUT" >&2
		tssevictcontrol -hi o -ho "${HANDLE}" -hp "${TPM_PERSISTENT_KEY_INDEX}" \
			${TPM_OWNER_PASSWORD:+-pwda "$(echo -en "${TPM_OWNER_PASSWORD}")"} ${VERBOSE+-v} >&2 || exit 1

		tssflushcontext -ha "${HANDLE}" ${VERBOSE+-v} >&2 || exit 1
		tssreadpublic -ho "${TPM_PERSISTENT_KEY_INDEX}" -opem "${STATEDIR}/tpmpubkey.persist.pem" ${VERBOSE+-v} >&2 || exit 1
	fi

	# The following tools cannot use the tpm_proxy
	export TPM_DEVICE="${ORIG_TPM_DEVICE}"
	export TPM_INTERFACE_TYPE="${ORIG_TPM_INTERFACE_TYPE}"

	create_tpm2_key -p "${TPM_PERSISTENT_KEY_INDEX}" --rsa "${TPMKEYFILE}" >&2 || exit 1
	TPMKEYURI="ibmtss2:${TPMKEYFILE}"
	# needs to go into ${STATEDIR}/tpmkeyurl for server.py
	echo -n "${TPMKEYURI}" > "${STATEDIR}/tpmkeyurl"

	openssl rsa -inform engine -engine tpm2 -pubout -in "${TPMKEYFILE}" -out "${STATEDIR}/tpmpubkey.pem"
	openssl req -engine tpm2 -new -key "${TPMKEYFILE}" -keyform engine -subj "/CN=vtpm2-jwt-server" -out "${STATEDIR}/server.csr" -reqexts v3_req -config <(cat ${TSIOPENSSLCNF} )
fi
