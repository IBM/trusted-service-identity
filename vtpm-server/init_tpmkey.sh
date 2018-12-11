#!/usr/bin/env bash

DIR=$(dirname "$0")

STATEDIR=${STATEDIR:-/tmp}

TPMTOOL=/bin/tpmtool

# echo "DIR=$DIR STATEDIR=$STATEDIR SRK_PASSWORD=$SRK_PASSWORD OWNER_PASSWORD=$OWNER_PASSWORD" >&2

if [ -f ${STATEDIR}/tpm_initialized ]; then
	exit 0
fi

source ${DIR}/tcsd_swtpm.sh
if ! [ -c /dev/tpm0 ] || [ -n "${USE_SWTPM}" ]; then
	# start and setup tcsd + swtpm
	setup_tcsd "${STATEDIR}" "${OWNER_PASSWORD}" "${SRK_PASSWORD}" "1"
else
	is_tpm_owned /dev/tpm0
	owned=$?
	if [ $owned -eq 1 ]; then
		if [ ! -f ${STATEDIR}/system.data ]; then
			if [ -z "$SRK_PASSWORD" ]; then
				cp ${DIR}/system.data.noauth ${STATEDIR}/system.data
			else
				cp ${DIR}/system.data.auth ${STATEDIR}/system.data
			fi
		fi
	fi
	# start and setup tcsd + hwtpm
	setup_tcsd "${STATEDIR}" "${OWNER_PASSWORD}" "${SRK_PASSWORD}" "0"
fi
[ $? -ne 0 ] && exit 1

KEY_PASSWORD="${SRK_PASSWORD}"
if [ -z "${SRK_PASSWORD}" ]; then
	params="--srk-well-known"
fi
msg=$(run_tpmtool "${SRK_PASSWORD}" "${KEY_PASSWORD}" ${params} --generate-rsa --register --signing)
if [ $? -ne 0 ]; then
	echo "Could not create TPM signing key."
	echo "${msg}"
	exit 1
fi
tpmkeyurl=$(echo "$msg" | sed -n 's/\(tpmkey:uuid=[^;]*\);.*/\1/p')
if [ -z "${tpmkeyurl}" ]; then
	echo "Could not grab TPM key url from tpmtool output."
	echo "${msg}"
	exit 1
fi

msg=$(run_tpmtool "${SRK_PASSWORD}" "${KEY_PASSWORD}" ${params} --pubkey "${tpmkeyurl}" --outfile ${STATEDIR}/tpmpubkey)
if [ $? -ne 0 ]; then
	echo "Could not get public key of TPM key."
	echo "${msg}"
	exit 1
fi

echo ${tpmkeyurl} > ${STATEDIR}/tpmkeyurl

touch ${STATEDIR}/tpm_initialized

stop_tcsd

exit 0

