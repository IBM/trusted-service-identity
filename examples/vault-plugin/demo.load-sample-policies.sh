#!/bin/bash

# Trusted Service Identiy plugin name
export PLUGIN="vault-plugin-auth-ti-jwt"

## create help menu:
helpme()
{
  cat <<HELPMEHELPME
Make sure ROOT_TOKEN and VAULT_ADDR environment variables are set.
export ROOT_TOKEN=
export VAULT_ADDR=(vault address in format http://vault.server:8200)

HELPMEHELPME
}

loadVault()
{
  #docker run -d --name=dev-vault -v ${PWD}/local.json:/vault/config/local.json -v ${PWD}/pkg/linux_amd64/${PLUGIN}:/plugins/${PLUGIN} -p 127.0.0.1:8200:8200/tcp vault
  echo "Root Token: ${ROOT_TOKEN}"
  vault login ${ROOT_TOKEN}

  export MOUNT_ACCESSOR=$(curl --header "X-Vault-Token: ${ROOT_TOKEN}"  --request GET ${VAULT_ADDR}/v1/sys/auth | jq -r '.["trusted-identity/"].accessor')

  # Use policy templates to create policy files.
  # The example below uses 3 different policies with the following constraints:
  #  - all - uses cluster-region, cluster-name, namespace and images
  #  - n - uses cluster-region, cluster-name, namespace
  #  - r - uses cluster-region

  # replace mount accessor in policy
  sed "s/<%MOUNT_ACCESSOR%>/$MOUNT_ACCESSOR/g" ti-policy.all.hcl.tpl > ti-policy.all.hcl
  sed "s/<%MOUNT_ACCESSOR%>/$MOUNT_ACCESSOR/g" ti-policy.n.hcl.tpl > ti-policy.n.hcl
  sed "s/<%MOUNT_ACCESSOR%>/$MOUNT_ACCESSOR/g" ti-policy.r.hcl.tpl > ti-policy.r.hcl

  # write policy to grant access to secrets
  vault policy write ti-policy-all ti-policy.all.hcl
  vault policy read ti-policy-all
  vault policy write ti-policy-n ti-policy.n.hcl
  vault policy read ti-policy-n
  vault policy write ti-policy-r ti-policy.r.hcl
  vault policy read ti-policy-r

  # create role to associate policy with login
  # vault write auth/trusted-identity/role/demo bound_subject="wsched@us.ibm.com" user_claim="pod" policies=ti-policy
  # vault write auth/trusted-identity/role/demo bound_subject="wsched@us.ibm.com" user_claim="pod" metadata_claims="cluster-region" policies=ti-policy
  # *NOTE* the first role MUST include all the metadata that would be used by other roles/policies, not only the first one.
  vault write auth/trusted-identity/role/demo bound_subject="wsched@us.ibm.com" user_claim="pod" metadata_claims="cluster-name,cluster-region,namespace,images" policies=ti-policy-all
  vault read auth/trusted-identity/role/demo

  vault write auth/trusted-identity/role/demo-n bound_subject="wsched@us.ibm.com" user_claim="pod" metadata_claims="cluster-name,cluster-region,namespace,images" policies=ti-policy-n
  vault read auth/trusted-identity/role/demo-n

  vault write auth/trusted-identity/role/demo-r bound_subject="wsched@us.ibm.com" user_claim="pod" metadata_claims="cluster-region" policies=ti-policy-r
  vault read auth/trusted-identity/role/demo-r
}

# validate the arguments
if [[ "$ROOT_TOKEN" == "" || "$VAULT_ADDR" == "" ]] ; then
  echo "ROOT_TOKEN and VAULT_ADDR must be set"
  helpme
else
  loadVault
fi
