#!/bin/sh
STATEDIR=${STATEDIR:-/host/tsi-secure}

start_server() {
  if ps -ef | grep flask | grep -v grep; then
    echo "web server already running"
  else
    cd /usr/local/bin || exit
    FLASK_APP=/web-server-pub.py python -m flask run --host=0.0.0.0 --port=5000 &
  fi
}

stop_server() {
  if ps -ef | grep flask | grep -v grep; then
    echo "stopping the running web server..."
    kill -9 $(ps -ef |grep flask | grep -v grep | awk '{print $2}')
  else
    echo "web server not running"
  fi
}

while true
 do
  NOW=$(date +%s)
  echo $NOW
  if [ -f /host/tsi-secure/x5c ] ; then
    echo "x5c file exists"
    stop_server
  else
    echo "x5c file does not exist"
    start_server
  fi
  sleep 30
done
