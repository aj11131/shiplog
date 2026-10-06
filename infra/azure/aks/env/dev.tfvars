# Settings for the "dev" AKS environment. None of these are secrets.
# tfstate_resource_group / tfstate_storage_account come from TF_VAR_* (CI) or backend.local.hcl docs.
environment    = "dev"
location       = "centralus"
node_vm_size   = "Standard_B2als_v2"
node_min_count = 2
node_max_count = 3

# Entra ID object IDs allowed to administer the cluster with kubectl
# (find yours with: az ad signed-in-user show --query id -o tsv).
cluster_admin_object_ids = [
  "2d69358a-06c0-411a-ad21-a1d044f07ed1",
]
