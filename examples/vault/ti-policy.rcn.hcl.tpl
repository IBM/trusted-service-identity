#  This policy template controls the path using:
#  * region
#  * cluster-name
#  * namespace

# Policy controlling cluster-region,cluster-name and namespace
path "secret/data/tsi-rcn/{{identity.entity.aliases.<%MOUNT_ACCESSOR%>.metadata.region}}/{{identity.entity.aliases.<%MOUNT_ACCESSOR%>.metadata.cluster-name}}/{{identity.entity.aliases.<%MOUNT_ACCESSOR%>.metadata.namespace}}/*" {
  # list allows listing the secrets:
  # capabilities = ["read", "list"]
  capabilities = ["read"]
}
