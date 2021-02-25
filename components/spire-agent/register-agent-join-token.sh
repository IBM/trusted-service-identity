#!/bin/sh -x

while true; do
  TOKEN=$(cat /run/spire/token/$HOST_IP)
  if [ "$TOKEN" == "" ]; then
    echo "No join token provided. Waiting 10 secs..."
    sleep 10
    continue
  fi
  /opt/spire/bin/spire-agent run -config /run/spire/config/agent.conf -socketPath /run/spire/sockets/agent.sock \
-joinToken  ${TOKEN}
 RT=$?
 if [ "$RT" != "0" ]; then
   echo "No valid token provided. Waiting 10 secs..."
   sleep 10
   continue
  fi

done
