#  This policy template controls the path using:
#  * cluster-region

path "secret/data/ti-demo-r/{{identity.entity.aliases.<%MOUNT_ACCESSOR%>.metadata.cluster-region}}/*" {
  capabilities = ["read"]
}
