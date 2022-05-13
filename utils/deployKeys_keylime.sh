#!/bin/bash
UC=/root/undercloud.yml
MZ=/root/mzone.yml

# to get the status of the Keylime cluster:
# keylime-op -u /root/undercloud.yml -m /root/mzone.yml -o status

# since we are processing all the nodes at once, deactive them all:
keylime-op -u ${UC} -m ${MZ} -o deactivate # > /dev/null 2>&1
CLUSTER_STATE=$(keylime-op -u ${UC} -m ${MZ} -o status | jq -r '.concise')
while [[ ${CLUSTER_STATE} != "inactive" ]]
do
  # wait until all the notes are deactivated
  keylime-op -u ${UC} -m ${MZ} -o wait --wait-pass inactive --wait-fail= --wait-interval=5 --wait-maxcount=3 > /dev/null 2>&1
  CLUSTER_STATE=$(keylime-op -u ${UC} -m ${MZ} -o status | jq -r '.concise')
done

# get all the nodes for x509 deployment
NODES=$(keylime-op -u ${UC} -m ${MZ} -o status | jq -r '.status | keys[]')
for NODE in $NODES
do
  echo "*** Processing $NODE...."
  ./x509-conf/createNodeScript.sh $NODE
  RT=$?
  if [ $RT -ne 0 ]; then
    echo "Error executing \"createNodeScript.sh $NODE\" script"
    exit 1
  fi
  # keylime-op -u ${UC} -m ${MZ} -o deactivate -n $NODE
  # NODE_STATE=$(keylime-op -u ${UC} -m ${MZ} -o status -n $NODE | jq -r '.status[]')
  # while [[ ${NODE_STATE} != "inactive" ]]

  # deploy the script to the nodes
  keylime-op -u ${UC} -m ${MZ} -o autorun -s `pwd`/scripts/${NODE}.sh -n $NODE
  keylime-op -u ${UC} -m ${MZ} -o wait --wait-pass inactive --wait-fail= --wait-interval=5 --wait-maxcount=3 > /dev/null 2>&1
  # keylime-op -u ${UC} -m ${MZ} -o activate -n $NODE
  # keylime-op -u ${UC} -m ${MZ} -o wait --wait-pass inactive --wait-fail= --wait-interval=5 --wait-maxcount=3
  echo "*** Done with $NODE!"
done
keylime-op -u ${UC} -m ${MZ} -o activate
CLUSTER_STATE=$(keylime-op -u ${UC} -m ${MZ} -o status | jq -r '.concise')
while [[ ${CLUSTER_STATE} != "verified" ]]
do
  # wait until all the notes are activated
  keylime-op -u ${UC} -m ${MZ} -o wait --wait-pass inactive --wait-fail= --wait-interval=5 --wait-maxcount=3 > /dev/null 2>&1
  CLUSTER_STATE=$(keylime-op -u ${UC} -m ${MZ} -o status | jq -r '.concise')
done

keylime-op -u ${UC} -m ${MZ} -o status
