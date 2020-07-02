#!/bin/bash

## create help menu:
helpme()
{
  cat <<HELPMEHELPME
This script displays the current TSI claims

syntax:
   $0 [pod-to-inspect] [namespace]

where:
      [pod-to-inspect] - name of the application pod to review the claims
      [namespace]   - namespace of the application pod

HELPMEHELPME
}

# {
#   "cluster-name": "my-cluster-name",
#   "region": "eu-de",
#   "exp": 1590494405,
#   "iat": 1590494345,
#   "images": "30beed0665d9cb4df616cca84ef2c06d2323e02869fcca8bbfbf0d8c5a3987cc",
#   "images-names": "ubuntu@sha256:250cc6f3f3ffc5cdaa9d8f4946ac79821aafb4d3afc93928f0de9336eba21aa4",
#   "iss": "wsched@us.ibm.com",
#   "machineid": "b46e165c32d342d9896d9eeb43c4d5dd",
#   "namespace": "test",
#   "pod": "myubuntu-6756d665bc-cb49l",
#   "sub": "wsched@us.ibm.com"
# }
# root@myubuntu-6756d665bc-cb49l:/# cat jwt/token | cut -d"." -f2 |base64 --decode |jq -r '.images'
# 30beed0665d9cb4df616cca84ef2c06d2323e02869fcca8bbfbf0d8c5a3987cc

# validate the arguments
if [[ "$1" == "-?" || "$1" == "-h" || "$1" == "--help" || "$2" == "" ]] ; then
    helpme
    exit 1
else
  POD="$1"
  NS="$2"
fi

CLAIMS=$(kubectl -n "$NS" exec -it "$POD" -c jwt-sidecar -- sh -c 'cat jwt/token | cut -d"." -f2 |base64 --decode | jq')
echo "$CLAIMS"
