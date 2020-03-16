#!/bin/sh
# this script checks if X5c file exists.
# if YES, the Private server starts and Public server shuts down
# if NO, the Public server starts and Private server shuts down
WAIT_SECS=30
STATEDIR="${STATEDIR:-/tmp}"
X5CFILE="${STATEDIR}/x5c"
SOCKETFILE="/host/sockets/app.sock"

cmd_priv_server_on="ps -ef | grep uwsgi | grep -v grep"
cmd_pub_server_on="ps -ef | grep flask | grep -v grep"

start_pub_server() {
  if [[ $(eval $cmd_pub_server_on) ]]; then
    echo "web server already running" > /dev/null # for debugging...
  else
    cd /usr/local/bin || exit
    FLASK_APP=/jss-server-pub.py python -m flask run --host=0.0.0.0 --port=5000 &
  fi
}

start_priv_server() {
  if [[ $(eval $cmd_priv_server_on) ]]; then
    echo "socket server already running" > /dev/null # for debugging...
  else
    cd /usr/local/bin || exit
    uwsgi --http-socket ${SOCKETFILE} --chmod-socket=666 --manage-script-name --mount /=jss-server-priv:app --plugins python &
    echo "wait for the socket file to be created then change its security context..."
    sleep 15
    chcon -t container_file_t ${SOCKETFILE}
  fi
}

stop_pub_server() {
  if [[ $(eval $cmd_pub_server_on) ]]; then
    echo "stopping the running web server..."
    kill -9 $(ps -ef |grep flask | grep -v grep | awk '{print $2}')
  fi
}

stop_priv_server() {
  if [[ $(eval $cmd_priv_server_on) ]]; then
    echo "stopping the running socket server..."
    kill -9 $(ps -ef |grep uwsgi | grep -v grep | awk '{print $2}')
  fi
}

while true
 do
  # NOW=$(date +%s)
  # echo "${NOW}"
  if [ -f "${X5CFILE}" ] ; then
    # echo "x5c file exists"
    start_priv_server
    stop_pub_server
  else
    # echo "x5c file does not exist"
    start_pub_server
    stop_priv_server
  fi
  sleep ${WAIT_SECS}
done
