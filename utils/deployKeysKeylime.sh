#!/bin/bash
function usage {
    echo "$0 [node]"
    echo "where "
    echo " node - name of the node to deploy keys"
    exit 1
}
[[ -z $1 ]] && usage

keylime-op -u undercloud.yml -m mzone.yml -o deactivate -n $NODE
keylime-op -u undercloud.yml -m mzone.yml -o autorun -s `pwd`/script/${NODE}.sh -n $NODE
keylime-op -u undercloud.yml -m mzone.yml -o activate -n $NODE

keylime-op -u undercloud.yml -m mzone.yml -o status
