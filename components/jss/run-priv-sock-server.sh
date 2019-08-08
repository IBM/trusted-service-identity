#!/bin/sh
STATEDIR=${STATEDIR:-/host/tsi-secure}
cd /usr/local/bin || exit
uwsgi --http-socket /sockets/app.sock --chmod-socket=666 --manage-script-name --mount /=web-server-priv:app --plugins python 
