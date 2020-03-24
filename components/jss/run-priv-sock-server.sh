#!/bin/sh
SOCKETFILE="/host/sockets/app.sock"
cd /usr/local/bin || exit
uwsgi --http-socket ${SOCKETFILE} --chmod-socket=666 --manage-script-name --mount /=web-server-priv:app --plugins python &
echo "wait for the socket file to be created then change its security context..."
while [ ! -S ${SOCKETFILE} ]; do
  sleep 5
done
chcon -t container_file_t ${SOCKETFILE}
echo "now wait forever..."
sleep infinity
