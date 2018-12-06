#!/usr/bin/env bash

DIR="$(dirname "$0")"
STATEDIR=${STATEDIR:-/tmp}

init_tpmkey.sh
[ $? -ne 0 ] && {
	echo "Failed to initialize TPM key"
}

source ${DIR}/tcsd_swtpm.sh
if ! [ -c /dev/tpm0 ] || [ -n "${USE_SWTPM}" ]; then
	# start tcsd + swtpm
	start_tcsd "${STATEDIR}" "1"
else
	start_tcsd "${STATEDIR}" "0"
fi

unset GNUTLS_PIN
if [ -n "${SRK_PASSWORD}" ]; then
	export GNUTLS_PIN="${SRK_PASSWORD}"
fi
cd /usr/local/bin || exit
./run-server.sh
