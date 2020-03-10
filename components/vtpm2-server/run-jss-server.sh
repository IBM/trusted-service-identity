#!/bin/sh
# this script checks if X5c file exists.
# if YES, the Private server starts and Public server shuts down
# if NO, the Public server starts and Private server shuts down
REPEAT_SECS=30
STATEDIR="${STATEDIR:-/tmp}"
X5CFILE="${STATEDIR}/x5c"

start_pub_server() {
  if ps -ef | grep flask | grep -v grep; then
    echo "web server already running"
  else
    cd /usr/local/bin || exit
    FLASK_APP=/jss-server-pub.py python -m flask run --host=0.0.0.0 --port=5000 &
  fi
}

start_priv_server() {
  if ps -ef | grep uwsgi | grep -v grep; then
    echo "socket server already running"
  else
    cd /usr/local/bin || exit
    uwsgi --http-socket /host/sockets/app.sock --chmod-socket=666 --manage-script-name --mount /=jss-server-priv:app --plugins python &
  fi
}

stop_pub_server() {
  if ps -ef | grep flask | grep -v grep; then
    echo "stopping the running web server..."
    kill -9 $(ps -ef |grep flask | grep -v grep | awk '{print $2}')
  else
    echo "web server not running"
  fi
}

stop_priv_server() {
  if ps -ef | grep uwsgi | grep -v grep; then
    echo "stopping the running socket server..."
    kill -9 $(ps -ef |grep uwsgi | grep -v grep | awk '{print $2}')
  else
    echo "socket server not running"
  fi
}

while true
 do
  NOW=$(date +%s)
  echo "${NOW}"
  if [ -f "${X5CFILE}" ] ; then
    echo "x5c file exists"
    start_priv_server
    stop_pub_server
  else
    echo "x5c file does not exist"
    start_pub_server
    stop_priv_server
  fi
  sleep ${REPEAT_SECS}
done
