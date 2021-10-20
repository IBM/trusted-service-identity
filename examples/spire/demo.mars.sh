#!/bin/bash
# this script requires https://github.com/duglin/tools/tree/main/demoscript
declare DEMOFILE=/usr/local/bin/demoscript
if [ ! -f "$DEMOFILE" ]; then
    echo "$DEMOFILE does not exist."
    exit 1
fi
source ${DEMOFILE}

# bin/spire-agent api fetch jwt -audience mys3 -socketPath /run/spire/sockets/agent.sock
# vi token.jwt # get JWT token
# bin/spire-agent api fetch jwt -audience mys3 -socketPath /run/spire/sockets/agent.sock  | sed -n '2p' | x
# args > token.jwt
#
#
# AWS_ROLE_ARN=arn:aws:iam::581274594392:role/mars-mission-role AWS_WEB_IDENTITY_TOKEN_FILE=token.jwt aws s3 cp s3://mars-spire/mars.txt top-secret.txt

doit "/opt/spire/bin/spire-agent api fetch jwt -audience mys3 -socketPath /run/spire/sockets/agent.sock"
doit --noexec "/opt/spire/bin/spire-agent api fetch jwt -audience mys3 -socketPath /run/spire/sockets/agent.sock | sed -n '2p' | xargs > token.jwt"
/opt/spire/bin/spire-agent api fetch jwt -audience mys3 -socketPath /run/spire/sockets/agent.sock | sed -n '2p' | xargs > token.jwt
# doit cat token.jwt
doit AWS_ROLE_ARN=arn:aws:iam::581274594392:role/mars-mission-role AWS_WEB_IDENTITY_TOKEN_FILE=token.jwt aws s3 cp s3://mars-spire/mars.txt top-secret.txt
doit cat top-secret.txt
