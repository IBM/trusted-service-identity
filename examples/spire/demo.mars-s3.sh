#!/bin/bash

# this script requires https://github.com/duglin/tools/tree/master/demoscript
# or https://github.com/mrsabath/tools/tree/master/demoscript
declare DEMOFILE=/usr/local/bin/demoscript
if [ ! -f "$DEMOFILE" ]; then
    echo "$DEMOFILE does not exist."
    exit 1
fi
source "${DEMOFILE}"

AG_SOCK=${AG_SOCK:-"/run/spire/sockets/agent.sock"}
S3_AUD=${S3_AUD:-"mys3"}
S3_ROLE=${S3_ROLE:-"arn:aws:iam::581274594392:role/mars-mission-role-01"}
S3_CMD=${S3_CMD:-"aws s3 cp s3://mars-spire/mars.txt top-secret.txt"}
S3_EXE=${S3_EXE:-"cat top-secret.txt"}

# bin/spire-agent api fetch jwt -audience mys3 -socketPath /run/spire/sockets/agent.sock
# vi token.jwt # get JWT token
# bin/spire-agent api fetch jwt -audience mys3 -socketPath /run/spire/sockets/agent.sock  | sed -n '2p' | x
# args > token.jwt
# AWS_ROLE_ARN=arn:aws:iam::581274594392:role/mars-mission-role AWS_WEB_IDENTITY_TOKEN_FILE=token.jwt aws s3 cp s3://mars-spire/mars.txt top-secret.txt

# show the JWT token
doit "/opt/spire/bin/spire-agent api fetch jwt -audience $S3_AUD -socketPath $AG_SOCK"

# parse the JWT token
doit --noexec "/opt/spire/bin/spire-agent api fetch jwt -audience $S3_AUD -socketPath $AG_SOCK | sed -n '2p' | xargs > token.jwt"
/opt/spire/bin/spire-agent api fetch jwt -audience "$S3_AUD" -socketPath "$AG_SOCK" | sed -n '2p' | xargs > token.jwt

# use the JWT token to request S3 content
doit "AWS_ROLE_ARN=$S3_ROLE AWS_WEB_IDENTITY_TOKEN_FILE=token.jwt $S3_CMD"
doit "$S3_EXE"
