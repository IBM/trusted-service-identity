#!/usr/bin/env bash

DIR="$(dirname "$0")"
STATEDIR=${STATEDIR:-/tmp}

init_tpmkey.sh
[ $? -ne 0 ] && {
	echo "Failed to initialize TPM key"
	exit 1
}

source ${DIR}/tcsd_swtpm.sh
if ! [ -c /dev/tpm0 ] || [ -n "${USE_SWTPM}" ]; then
	# start tcsd + swtpm
	start_tcsd "${STATEDIR}" "1"
else
	resetlockvalue -pwdo ${OWNER_PASSWORD}
	start_tcsd "${STATEDIR}" "0"
fi

unset GNUTLS_PIN
if [ -n "${SRK_PASSWORD}" ]; then
	export GNUTLS_PIN="${SRK_PASSWORD}"
fi

# if first parameter is then given key, take it, otherwise take
# it from the file
if [[ $1 =~ tpmkey:uuid= ]]; then
	key=$1
	shift
else
	key="$(cat ${STATEDIR}/tpmkeyurl)"
fi

gen-jwt.py "$key" $@

stop_tcsd
