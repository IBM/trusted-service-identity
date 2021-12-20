#  This policy template controls the path using:
#  * region
#  * images

path "secret/data/tsi-ri/{{identity.entity.aliases.<%MOUNT_ACCESSOR%>.metadata.region}}/{{identity.entity.aliases.<%MOUNT_ACCESSOR%>.metadata.images}}/*" {
  capabilities = ["read"]
}
