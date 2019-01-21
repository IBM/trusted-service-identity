
SWTPM_SERVER_PORT=65426

export TPM_SERVER_NAME=localhost
export TPM_SERVER_TYPE=${TPM_SERVER_TYPE:-raw}
export TPM_INTERFACE_TYPE=${TPM_INTERFACE_TYPE:-socsim}
export TPM_COMMAND_PORT=${SWTPM_SERVER_PORT}

if [ "${TPM_INTERFACE_TYPE}" == "socsim" ]; then
	swtpm socket \
		--tpm2 \
		--tpmstate dir=${STATEDIR} \
		--flags not-need-init \
		--daemon \
		--server type=tcp,port=${TPM_COMMAND_PORT}
fi

TPMKEYFILE=${STATEDIR}/tpm.key
if ! [ -f ${TPMKEYFILE} ]; then
	tssstartup -c || exit 1
	tsscreateprimary -hi o -st -rsa &>/dev/null || exit 1
	tssevictcontrol -hi o -ho 80000000 -hp 81000001 || exit 1
	tssflushcontext -ha 80000000 || exit 1
	tssreadpublic -ho 81000001 -opem /tmp/tpmpubkey.persist.pem || exit 1

	create_tpm2_key -p 81000001 --rsa ${TPMKEYFILE} || exit 1
	TPMKEYURI="ibmtss2:${TPMKEYFILE}"
	# needs to go into /tmp/tpmkeyurl for server.py
	echo -n ${TPMKEYURI} > /tmp/tpmkeyurl

	openssl rsa -inform engine -engine tpm2 -pubout -in ${TPMKEYFILE} -out ${STATEDIR}/tpmpubkey.pem
fi
