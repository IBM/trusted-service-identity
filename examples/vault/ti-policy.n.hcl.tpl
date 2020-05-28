#  This policy template controls the path using:
#  * cluster-region
#  * cluster-name
#  * namespace

# Policy controlling cluster-region,cluster-name and namespace
path "secret/data/ti-demo-n/{{identity.entity.aliases.<%MOUNT_ACCESSOR%>.metadata.cluster-region}}/{{identity.entity.aliases.<%MOUNT_ACCESSOR%>.metadata.cluster-name}}/{{identity.entity.aliases.<%MOUNT_ACCESSOR%>.metadata.namespace}}/*" {
  capabilities = ["read", "list"]
}
