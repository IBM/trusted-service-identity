#!/bin/bash
function usage {
    echo "$0 [node]"
    echo "where "
    echo " node - name of the node to deploy keys"
    exit 1
}
[[ -z $1 ]] && usage
NODE=$1

keylime-op -u /root/undercloud.yml -m /root/mzone.yml -o deactivate -n $NODE
keylime-op -u /root/undercloud.yml -m /root/mzone.yml -o autorun -s `pwd`/${NODE}.sh -n $NODE
keylime-op -u /root/undercloud.yml -m /root/mzone.yml -o activate -n $NODE

keylime-op -u /root/undercloud.yml -m /root/mzone.yml -o status
