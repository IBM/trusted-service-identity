#!/bin/bash
UC=/root/undercloud.yml
MZ=/root/mzone.yml

# setup access to the Tornjak Server:
if [[ "$TORNJAK" == "" ]] ; then
  echo "TORNJAK env. variable must be set (e.g.)"
  echo "export TORNJAK=http://"
  exit 1
fi


# to get the status of the Keylime cluster:
# keylime-op -u /root/undercloud.yml -m /root/mzone.yml -o status
FAGENT=

while true
do
  CLUSTER_STATE_F=$(keylime-op -u ${UC} -m ${MZ} -o status)
  CLUSTER_STATE=$(echo $CLUSTER_STATE_F | jq -r '.concise')
  if [ "${CLUSTER_STATE}"  == "verified" ]; then
     echo "All good, sleep for 10 secs..."
     sleep 10

  elif  [ "${CLUSTER_STATE}"  == "failed" ]; then

# NODES=$(echo $CLUSTER_STATE_F | jq -r '.status' | jq 'with_entries(.value = "failed")' | jq 'keys[]')
   NODES=$(echo $CLUSTER_STATE_F | jq -r '.status' | jq -r '. | to_entries[] | select(.value == "failed") |.key')
   for NODE in $NODES
    do
      echo "*** Processing node $NODE that failed attestation...."
      # curl -s http://tornjak-http-tornjak.spire-01-9d995c4a8c7c5f281ce13d5467ff6a94-0000.us-east.containers.appdomain.cloud/api/agent/list | jq > /tmp/agents.json
      curl -s ${TORNJAK}/api/agent/list | jq > /tmp/agents.json
      echo "*** All Agents received"
      NODEX="subject:cn:$NODE"
      FAGENT=$(cat /tmp/agents.json | jq --arg nodex $NODEX -r '.agents[] | select(.selectors[].value==$nodex) | .id.path')

      #cat /tmp/agents.json | jq --arg nodex "$TT" '.agents[] | select(.selectors[].value==$nodex) | .id.path | $nodex'
      #export NODEX="$NODE"
      #FAGENT=$(cat /tmp/agents.json | jq -n  '.agents[] | select(.selectors[].value=="subject:cn:"env.NODEX) | .id.path')
      #FAGENT=$(cat /tmp/agents.json | jq -r "'"'.agents[] | select(.selectors[].value=="subject:cn:'"$NODE"'") | .id.path'"')"
      #FAGENT=$(cat /tmp/agents.json | jq -r '.agents[] | select(.selectors[].value=="subject:cn:$NODE") | .id.path'
      echo "$FAGENT"
      # RESULT=$(curl -s -X POST http://tornjak-http-tornjak.spire-01-9d995c4a8c7c5f281ce13d5467ff6a94-0000.us-east.containers.appdomain.cloud/api/agent/ban -H 'Content-Type: application/json' -d  '{"id":{"trust_domain":"openshift.space-x.com","path":"'"$FAGENT"'"}}')
      RESULT=$(curl -s -X POST ${TORNJAK}/api/agent/ban -H 'Content-Type: application/json' -d  '{"id":{"trust_domain":"openshift.space-x.com","path":"'"$FAGENT"'"}}')
      echo "RESULT: $RESULT"
      # ssh $NODE "rm /run/spire/x509/*.pem"
      # ssh $NODE "ls -l /run/spire/x509/"
      # since we can't trust the node anymore, it's compromised, we should not
      # bother with the cleanup, but let's just do it for fun:
      ssh -o LogLevel=quiet -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $NODE "rm /run/spire/x509/*.pem" 2>/dev/null
      ssh -o LogLevel=quiet -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $NODE "ls /run/spire/x509"
      echo "Cleanup of $NODE completed"
   done
    sleep 15
  else
    echo "Unknown state. Terminate..."
    exit 1
  fi


done
