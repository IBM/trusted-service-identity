#  This policy template controls the path using:
#  * cluster-region
#  * cluster-name
#  * namespace
#  * images

path "secret/data/ti-demo-all/{{identity.entity.aliases.<%MOUNT_ACCESSOR%>.metadata.cluster-region}}/{{identity.entity.aliases.<%MOUNT_ACCESSOR%>.metadata.cluster-name}}/{{identity.entity.aliases.<%MOUNT_ACCESSOR%>.metadata.namespace}}/{{identity.entity.aliases.<%MOUNT_ACCESSOR%>.metadata.images}}/*" {
  capabilities = ["read"]
}
