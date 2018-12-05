#!/usr/bin/env bash

DIR="$(dirname "$0")"
STATEDIR=${STATEDIR:-/tmp}

init_tpmkey.sh
[ $? -ne 0 ] && {
	echo "Failed to initialize TPM key"
}

if ! [ -c /dev/tpm0 ] || [ -n ${USE_SWTPM} ]; then
	# use tcsd + swtpm
	source ${DIR}/tcsd_swtpm.sh

	# start tcsd + swtpm
	start_tcsd "${STATEDIR}"
else
	echo "HW TPM support not implemented" >&2
	exit 1
fi

unset GNUTLS_PIN
if [ -n "${SRK_PASSWORD}" ]; then
	export GNUTLS_PIN="${SRK_PASSWORD}"
fi
gen-jwt.py "$(cat ${STATEDIR}/tpmkeyurl)" $@

stop_tcsd
