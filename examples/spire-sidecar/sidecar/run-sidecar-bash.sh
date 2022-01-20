#!/bin/bash

SOCKETFILE=${SOCKETFILE:-"/run/spire/sockets/agent.sock"}
CFGDIR=${CFGDIR:-"/run/db"}
ROLE=${ROLE:-"dbrole1"}
VAULT_ADDR=${VAULT_ADDR:-"http://tsi-vault.my-cluster-0123456789-0000.eu-de.containers.appdomain.cloud"}

WAIT=30

# method used to obtain a resource/file from vault, using jwt token (i.e. X-Vault-Token)
get_resource () {
    if [ "$?" == "0" ]; then
        if [[ $1 == *"json"* ]]; then
            # JSON dump
            curl --max-time 10 -s -H "X-Vault-Token: $VAULT_TOKEN" $VAULT_ADDR/v1/secret/data/$2 | jq -r ".data.data" > $CFGDIR/$1
        else
            # other files, beside JSON, need to be encoded to base64 prior to storing into Vault
            curl --max-time 10 -s -H "X-Vault-Token: $VAULT_TOKEN" $VAULT_ADDR/v1/secret/data/$2 | jq -r ".data.data.sha" | openssl base64 -d > $CFGDIR/$1
        fi
    fi
}

if [[ ! -f $1 ]]; then
    cat <<HELPMEHELPME
Utility that obtains a list of resources from Vault and saves them to a volume mount.
Syntax: ${0} <INPUT_FILE>
Where:
<INPUT_FILE> - path to file that would contain resources (required)
HELPMEHELPME
    exit 0
fi

# read each line into array (i.e. files)
mapfile -t files < $1


while true 
do
    # make sure the socket file exists before requesting a token
    while [ ! -S ${SOCKETFILE} ]; do
        sleep 5
    done
    # obtain the pod identity in JWT format from the Spire agent using a provided socket
    IDENTITY_TOKEN=$(/opt/spire/bin/spire-agent api fetch jwt -audience vault -socketPath $SOCKETFILE | sed -n '2p' | xargs)
    if [ -z "$IDENTITY_TOKEN" ]; then
        echo "IDENTITY_TOKEN not set"
        exit 0
    fi
    # For use with AWS S3:
    # the audience must be switched to 'mys3'
    # /opt/spire/bin/spire-agent api fetch jwt -audience mys3 -socketPath /run/spire/sockets/agent.sock > $RESP
    # AWS_ROLE_ARN=arn:aws:iam::581274594392:role/mars-mission-role AWS_WEB_IDENTITY_TOKEN_FILE=token.jwt aws s3 cp s3://mars-spire/db-config.json config.json
    # mv config.json $CFGFILE

    # Using identity JWT, obtain and extract client_token from Vault login service
    VAULT_TOKEN=$(curl --max-time 10 -s --request POST --data '{ "jwt": "'"${IDENTITY_TOKEN}"'", "role": "'"${ROLE}"'"}' "${VAULT_ADDR}"/v1/auth/jwt/login | jq -r  '.auth.client_token')
    if [ -z "$VAULT_TOKEN" ]; then
        echo "VAULT_TOKEN not set"
        exit 0
    fi

    filenames=() # will store only files names, used to check if they exists later
    for i in "${files[@]}"
    do
        tmp=$( echo "$i" | sed 's:.*/::' )
        filenames+=("$tmp")
        get_resource $tmp $i
    done

    success=1
    # check if all files were retrieved
    for i in "${filenames[@]}"
    do
        if [[ ! -f "$CFGDIR/$i" ]]; then
            success=0
        fi
    done

    if [ $success -eq 1 ]; then
        exit 0
    fi


    sleep "$WAIT"
done
