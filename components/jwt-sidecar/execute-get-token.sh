#!/usr/bin/env bash
mkdir /jwt
SOCKETFILE="/host/sockets/app.sock"

while true
 do
  # make sure the socket file exists before requesting a token
  while [ ! -S ${SOCKETFILE} ]; do
    sleep 5
  done
  echo -n '' > /tmp/claims
  echo -n "pod=$(cat /pod-metadata/ti-pod-name)&" >> /tmp/claims
  echo -n "namespace=$(cat /pod-metadata/ti-pod-namespace)&" >> /tmp/claims
  echo -n "images-names=$(cat /pod-metadata/tsi-images)&" >> /tmp/claims
  echo -n "images=$(cat /pod-metadata/tsi-images | sha256sum | awk '{print $1}')&" >> /tmp/claims
  echo -n "cluster-name=$(cat /pod-metadata/tsi-cluster-name)&" >> /tmp/claims
  echo -n "region=$(cat /pod-metadata/tsi-region)&" >> /tmp/claims
  echo -n "machineid=$(cat /host/machineid)" >> /tmp/claims

  curl -s --unix-socket ${SOCKETFILE} http://localhost/getJWT?"$(cat /tmp/claims)" > /jwt/token
  # make the wait 5 seconds shorter than JWT TTL
  sleep "$((${JWT_TTL_SEC}-5))"
done
