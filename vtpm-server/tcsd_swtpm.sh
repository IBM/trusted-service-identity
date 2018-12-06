#!/bin/sh

# Copyright (C) 2018 IBM Corporation
#
# Author: Stefan Berger
#
# This file is part of GnuTLS.
#
# GnuTLS is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation; either version 3 of the License, or (at
# your option) any later version.
#
# GnuTLS is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with GnuTLS; if not, write to the Free Software Foundation,
# Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.

SWTPM_SERVER_PORT=12345
SWTPM_CTRL_PORT=$((SWTPM_SERVER_PORT + 1))
SWTPM_PIDFILE=${workdir}/swtpm.pid
TCSD_LISTEN_PORT=12347
export TSS_TCSD_PORT=$TCSD_LISTEN_PORT

wait_for_file() {
	local filename="$1"
	local timeout="$2"

	local loops=$((timeout * 10)) loop=0

	while test $loop -lt $loops; do
		[ -f "$filename" ] && {
			#allow file to be written to
			sleep 0.2
			return 1
		}
		sleep 0.1
		loop=$((loop+1))
	done
	return 0
}

# Kill a process quietly
# @1: signal, e.g. -9
# @2: pid
kill_quiet() {
	local sig="$1"
	local pid="$2"

	sh -c "kill $sig $pid 2>/dev/null"
	return $?
}

# Terminate a process first using SIGTERM, wait 1s and if still avive use
# SIGKILL
# @1: pid
terminate_proc() {
	local pid="$1"

	local ctr=0

	kill_quiet -15 $pid
	while [ $ctr -lt 10 ]; do
		kill -0 $pid 2>/dev/null
		[ $? -ne 0 ] && return
		ctr=$((ctr + 1))
	done
	kill_quiet -9 $pid
	sleep 0.1
}

cleanup()
{
	stop_tcsd
	if [ -n "$workdir" ]; then
		rm -rf $workdir
	fi
}

start_swtpm()
{
	local workdir="$1"

	local res

	swtpm socket \
		--flags not-need-init \
		--pid file=$SWTPM_PIDFILE \
		--tpmstate dir=$workdir \
		--server type=tcp,port=$SWTPM_SERVER_PORT,disconnect \
		--ctrl type=tcp,port=$SWTPM_CTRL_PORT &

	if wait_for_file $SWTPM_PIDFILE 3; then
		echo "Starting the swtpm failed"
		return 1
	fi

	SWTPM_PID=$(cat $SWTPM_PIDFILE)
	kill -0 ${SWTPM_PID}
	if [ $? -ne 0 ]; then
		echo "swtpm must have terminated"
		return 1
	fi

	# Send TPM_Startup to TPM
	res="$(/bin/echo -en '\x00\xC1\x00\x00\x00\x0C\x00\x00\x00\x99\x00\x01' |
		ncat localhost ${SWTPM_SERVER_PORT} | od -tx1 -An)"
	exp=' 00 c4 00 00 00 0a 00 00 00 00'
	if [ "$res" != "$exp" ]; then
		echo "Did not get expected response from TPM_Startup(ST_CLEAR)"
		echo "expected: $exp"
		echo "received: $res"
		return 1
	fi

	return 0
}

stop_swtpm()
{
	if [ -n "$SWTPM_PID" ]; then
		terminate_proc $SWTPM_PID
		unset SWTPM_PID
	fi
}

start_tcsd()
{
	local workdir="$1"

	local tcsd_conf=$workdir/tcsd.conf
	local tcsd_system_ps_file=$workdir/system_ps_file
	local tcsd_pidfile=$workdir/tcsd.pid

	start_swtpm "$workdir"
	[ $? -ne 0 ] && return 1

	cat <<_EOF_ > $tcsd_conf
port = $TCSD_LISTEN_PORT
system_ps_file = $tcsd_system_ps_file
_EOF_

	chown tss:tss $tcsd_conf
	chmod 0600 $tcsd_conf

	bash -c "TCSD_USE_TCP_DEVICE=1 TCSD_TCP_DEVICE_PORT=$SWTPM_SERVER_PORT tcsd -c $tcsd_conf -e -f &>/dev/null & echo \$! > $tcsd_pidfile; wait" &
	BASH_PID=$!

	if wait_for_file $tcsd_pidfile 3; then
		echo "Could not get TCSD's PID file"
		return 1
	fi

	TCSD_PID=$(cat $tcsd_pidfile)
	return 0
}

stop_tcsd()
{
	if [ -n "$TCSD_PID" ]; then
		terminate_proc $TCSD_PID
		unset TCSD_PID
	fi
	stop_swtpm
}

run_tpm_takeownership()
{
	local owner_password="$1"
	local srk_password="$2"

	local prg out rc
	local parm_z=""

	if [ -z "$srk_password" ]; then
		parm_z="--srk-well-known"
	fi

	prg="set parm_z \"$parm_z\"
		spawn tpm_takeownership \$parm_z
		expect {
			\"Enter owner password:\"
				{ send \"$owner_password\n\" }
		}
		expect {
			\"Confirm password:\"
				{ send \"$owner_password\n\" }
		}
		if { \$parm_z == \"\" } {
			expect {
				\"Enter SRK password:\"
					{ send \"$srk_password\n\" }
			}
			expect {
				\"Confirm password:\"
					{ send \"$srk_password\n\" }
			}
		}
		expect {
			eof
		}
		catch wait result
		exit [lindex \$result 3]
	"
	out=$(expect -c "$prg")
	rc=$?
	echo "$out"
	return $rc
}

setup_tcsd()
{
	local workdir="$1"
	local owner_password="$2"
	local srk_password="$3"

	local msg

	start_tcsd "$workdir"
	[ $? -ne 0 ] && return 1

	tpm_createek
	[ $? -ne 0 ] && {
		echo "Could not create EK"
		return 1
	}
	msg="$(run_tpm_takeownership "$owner_password" "$srk_password")"
	[ $? -ne 0 ] && {
		echo "Could not take ownership of TPM"
		echo "$msg"
		return 1
	}
	return 0
}

run_tpmtool()
{
	local srk_password="$1"
	local key_password="$2"

	shift 2

	local prg out rc

	prg="spawn $TPMTOOL $@
		expect {
			\"Enter SRK password:\" {
				send \"$srk_password\n\"
				exp_continue
			}
			\"Enter key password:\" {
				send \"$key_password\n\"
				exp_continue
			}
			\"tpmkey:\" {
				exp_continue
			}
			eof
		}
		catch wait result
		exit [lindex \$result 3]
	"
	out=$(expect -c "$prg")
	rc=$?
	echo "$out"
	return $rc
}
