#!/bin/bash
/vault login -address=$(cat /keys/address) -tls-skip-verify $(cat /keys/root-token) && \
/vault delete -address=$(cat /keys/address) -tls-skip-verify auth/cert/certs/$1
