#!/bin/bash

helpme()
{
  cat <<HELPMEHELPME

Script ${0} requires following environment variables to be set:
  KEYSTORE_URL
  TARGET_URL

HELPMEHELPME
}

# validate the required env. variables
if [[ "$KEYSTORE_URL" == "" || "$KEYSTORE_URL" == "NOTSET" || "$TARGET_URL" == "" || "$TARGET_URL" == "NOTSET" ]] ; then
  helpme
  exit 1
fi

curl --header "Authorization: Bearer $(cat /jwt-tokens/token)"  --insecure ${KEYSTORE_URL} > all-claims

export USERNAME=$(curl --header "Authorization: Bearer $(cat /jwt-tokens/token)"  --insecure ${KEYSTORE_URL}/get/cloudant-key-name)
export API_KEY=$(curl --header "Authorization: Bearer $(cat /jwt-tokens/token)"  --insecure ${KEYSTORE_URL}/get/cloudant-key-value)
# we should get the TARGET_URL here as well

echo $USERNAME
echo $API_KEY
python ./cloudant-client.py
mkdir -p static/jwt-client
mv ./static/index.html.new ./static/jwt-client/index.html
