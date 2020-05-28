#  This policy template controls the path using:
#  * region

path "secret/data/tsi-r/{{identity.entity.aliases.<%MOUNT_ACCESSOR%>.metadata.region}}/*" {
  capabilities = ["read"]
}
