#  This policy template controls the path using:
#  * region
#  * cluster-name
#  * namespace
#  * images

path "secret/data/tsi-rcni/{{identity.entity.aliases.<%MOUNT_ACCESSOR%>.metadata.region}}/{{identity.entity.aliases.<%MOUNT_ACCESSOR%>.metadata.cluster-name}}/{{identity.entity.aliases.<%MOUNT_ACCESSOR%>.metadata.namespace}}/{{identity.entity.aliases.<%MOUNT_ACCESSOR%>.metadata.images}}/*" {
  capabilities = ["read"]
}
