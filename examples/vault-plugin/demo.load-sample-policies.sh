#!/bin/bash

# Trusted Servie Identiy plugin name
export PLUGIN="vault-plugin-auth-ti-jwt"
# test image name
export IMG="res-kompass-kompass-docker-local.artifactory.swg-devops.com/vault-cli:v0.1"
export IMGSHA=
# export IMGSHA="f36b6d491e0a62cb704aea74d65fabf1f7130832e9f32d0771de1d7c727a79cc"

# sha-256 encoded file name based on the OS:
if [[ "$OSTYPE" == "linux-gnu" ]]; then
  # Linux
  IMGSHA=$(echo -n "$IMG" | sha256sum | awk '{print $1}')
elif [[ "$OSTYPE" == "darwin"* ]]; then
  # Mac OSX
  IMGSHA=$(echo -n "$IMG" | shasum -a 256 | awk '{print $1}')
elif [[ "$OSTYPE" == "cygwin" ]]; then
  # POSIX compatibility layer and Linux environment emulation for Windows
  IMGSHA=
else
  # Unknown.
  IMGSHA=
fi

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



  #create role to associate policy with login
  # vault write auth/trusted-identity/role/demo bound_subject="wsched@us.ibm.com" user_claim="pod" policies=ti-policy
  # vault write auth/trusted-identity/role/demo bound_subject="wsched@us.ibm.com" user_claim="pod" metadata_claims="cluster-region" policies=ti-policy
  # TODO the first role MUST include all the metadata that would be used by other roles/policies, not only the first one.
  vault write auth/trusted-identity/role/demo bound_subject="wsched@us.ibm.com" user_claim="pod" metadata_claims="cluster-name,cluster-region,namespace,images" policies=ti-policy-all
  vault read auth/trusted-identity/role/demo

  vault write auth/trusted-identity/role/demo-n bound_subject="wsched@us.ibm.com" user_claim="pod" metadata_claims="cluster-name,cluster-region,namespace,images" policies=ti-policy-n
  vault read auth/trusted-identity/role/demo-n

  vault write auth/trusted-identity/role/demo-r bound_subject="wsched@us.ibm.com" user_claim="pod" metadata_claims="cluster-region" policies=ti-policy-r
  vault read auth/trusted-identity/role/demo-r


  # # write some data to be read later on
  # # testing rule `demo` with ti-policy-all
  vault kv put secret/ti-demo-all/eu-de/EUcluster/trusted-identity/${IMGSHA}/dummy all=EUcluster
  vault kv put secret/ti-demo-all/eu-de/XXcluster/trusted-identity/${IMGSHA}/dummy all=XXcluster
  vault kv put secret/ti-demo-all/dal01/UScluster/trusted-identity/${IMGSHA}/dummy all=dal01
  vault kv put secret/ti-demo-all/wdc01/UScluster/trusted-identity/${IMGSHA}/dummy all=wdc01

  vault kv get secret/ti-demo-all/eu-de/EUcluster/trusted-identity/${IMGSHA}/dummy
  vault kv get secret/ti-demo-all/eu-de/XXcluster/trusted-identity/${IMGSHA}/dummy
  vault kv get secret/ti-demo-all/dal01/UScluster/trusted-identity/${IMGSHA}/dummy
  vault kv get secret/ti-demo-all/wdc01/UScluster/trusted-identity/${IMGSHA}/dummy

  # testing rule demo-n with policy ti-policy-n
  vault kv put secret/ti-demo-n/eu-de/EUcluster/trusted-identity/dummy policy-n=EUcluster
  vault kv put secret/ti-demo-n/eu-de/XXcluster/trusted-identity/dummy policy-n=XXcluster
  vault kv put secret/ti-demo-n/dal01/UScluster/trusted-identity/dummy policy-n=dal01-UScluster
  vault kv put secret/ti-demo-n/wdc01/UScluster/trusted-identity/dummy policy-n=wdc01-UScluster

  vault kv get secret/ti-demo-n/eu-de/EUcluster/trusted-identity/dummy
  vault kv get secret/ti-demo-n/eu-de/XXcluster/trusted-identity/dummy
  vault kv get secret/ti-demo-n/dal01/UScluster/trusted-identity/dummy
  vault kv get secret/ti-demo-n/wdc01/UScluster/trusted-identity/dummy


  # testing rule demo-r with policy ti-demo-r
  vault kv put secret/ti-demo-r/eu-de/dummy region=eu-de
  vault kv put secret/ti-demo-r/dal01/dummy region=dal01
  vault kv put secret/ti-demo-r/wdc01/dummy region=wdc01

  # # for testing rule demo-r
  vault kv get secret/ti-demo-r/eu-de/dummy
  vault kv get secret/ti-demo-r/dal01/dummy
  vault kv get secret/ti-demo-r/wdc01/dummy
  }

# validate the arguments
if [[ "$ROOT_TOKEN" == "" || "$VAULT_ADDR" == "" ]] ; then
  echo "ROOT_TOKEN and VAULT_ADDR must be set"
  helpme
else
  loadVault
fi
