#!/bin/bash
/vault login -address=$(cat /skeys/address) -tls-skip-verify $(cat /keys/root-token) && \
/vault delete -address=$(cat /skeys/address) -tls-skip-verify auth/cert/certs/$1
