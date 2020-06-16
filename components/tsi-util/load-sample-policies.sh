#!/bin/bash

# Trusted Service Identiy plugin name
export PLUGIN="vault-plugin-auth-ti-jwt"

## create help menu:
helpme()
{
  cat <<HELPMEHELPME

  Syntax: ${0} <vault_addr> <vault_token>
  Where:
    vault_addr - vault address (or ingress) in format http://vault.server:8200
    token      - vault root token to setup the plugin

Or make sure ROOT_TOKEN and VAULT_ADDR are set as environment variables.
export ROOT_TOKEN=
export VAULT_ADDR=(vault address in format http://vault.server:8200)

HELPMEHELPME
}

loadVault()
{
  #docker run -d --name=dev-vault -v ${PWD}/local.json:/vault/config/local.json -v ${PWD}/pkg/linux_amd64/${PLUGIN}:/plugins/${PLUGIN} -p 127.0.0.1:8200:8200/tcp vault
  # echo "Root Token: ${ROOT_TOKEN}"
  vault login -no-print ${ROOT_TOKEN}
  RT=$?

  if [ $RT -ne 0 ] ; then
     echo "Vault login failed!"
     exit 1
  fi

  export MOUNT_ACCESSOR=$(curl --header "X-Vault-Token: ${ROOT_TOKEN}"  --request GET ${VAULT_ADDR}/v1/sys/auth | jq -r '.["trusted-identity/"].accessor')

  # Use policy templates to create policy files.
  # The example below uses 4 different policies with the following constraints:
  #  - rcni - uses region, cluster-name, namespace and images
  #  - rcn - uses region, cluster-name, namespace
  #  - ri - uses region and images
  #  - r - uses region only

  # replace mount accessor in policy
  sed "s/<%MOUNT_ACCESSOR%>/$MOUNT_ACCESSOR/g" /vault-tpl/tsi-policy.rcni.hcl.tpl > /vault-tpl/tsi-policy.rcni.hcl
  sed "s/<%MOUNT_ACCESSOR%>/$MOUNT_ACCESSOR/g" /vault-tpl/tsi-policy.rcn.hcl.tpl > /vault-tpl/tsi-policy.rcn.hcl
  sed "s/<%MOUNT_ACCESSOR%>/$MOUNT_ACCESSOR/g" /vault-tpl/tsi-policy.ri.hcl.tpl > /vault-tpl/tsi-policy.ri.hcl
  sed "s/<%MOUNT_ACCESSOR%>/$MOUNT_ACCESSOR/g" /vault-tpl/tsi-policy.r.hcl.tpl > /vault-tpl/tsi-policy.r.hcl

  # write policy to grant access to secrets
  vault policy write tsi-policy-rcni /vault-tpl/tsi-policy.rcni.hcl
  vault policy read tsi-policy-rcni
  vault policy write tsi-policy-rcn /vault-tpl/tsi-policy.rcn.hcl
  vault policy read tsi-policy-rcn
  vault policy write tsi-policy-ri /vault-tpl/tsi-policy.ri.hcl
  vault policy read tsi-policy-ri
  vault policy write tsi-policy-r /vault-tpl/tsi-policy.r.hcl
  vault policy read tsi-policy-r

  # create role to associate policy with login
  # we choosed to use one role, one policy association
  # *NOTE* the first role MUST include all the metadata that would be used by other roles/policies, not only the first one.
  vault write auth/trusted-identity/role/tsi-role-rcni bound_subject="wsched@us.ibm.com" user_claim="pod" metadata_claims="region,cluster-name,namespace,images" policies=tsi-policy-rcni
  vault read auth/trusted-identity/role/tsi-role-rcni

  vault write auth/trusted-identity/role/tsi-role-rcn bound_subject="wsched@us.ibm.com" user_claim="pod" metadata_claims="region,cluster-name,namespace" policies=tsi-policy-rcn
  vault read auth/trusted-identity/role/tsi-role-rcn

  vault write auth/trusted-identity/role/tsi-role-ri bound_subject="wsched@us.ibm.com" user_claim="pod" metadata_claims="region,images" policies=tsi-policy-ri
  vault read auth/trusted-identity/role/tsi-role-ri

  vault write auth/trusted-identity/role/tsi-role-r bound_subject="wsched@us.ibm.com" user_claim="pod" metadata_claims="region" policies=tsi-policy-r
  vault read auth/trusted-identity/role/tsi-role-r
}

# validate the arguments
if [[ "$1" != "" && "$2" != "" ]] ; then
  export VAULT_ADDR="$1"
  export ROOT_TOKEN="$2"
fi

if [[ "$ROOT_TOKEN" == "" || "$VAULT_ADDR" == "" ]] ; then
  echo "ROOT_TOKEN and VAULT_ADDR must be set"
  helpme
  exit 1
else
  loadVault
fi
