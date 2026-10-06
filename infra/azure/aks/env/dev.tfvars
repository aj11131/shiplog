# Settings for the "dev" AKS environment. None of these are secrets.
# tfstate_resource_group / tfstate_storage_account come from TF_VAR_* (CI) or your local environment.
environment = "dev"
location    = "centralus"

# The subscription's vCPU quota in centralus is 4 (total and per VM family), so:
#   2 nodes × 2 vCPU = 4: the whole quota. No autoscaling and no surge node during upgrades.
# After a quota increase, consider: node_autoscaling = { min = 2, max = 4 } and node_upgrade_surge = true
node_vm_size       = "Standard_D2als_v7"
node_count         = 2
node_autoscaling   = null
node_upgrade_surge = false

# Entra ID object IDs allowed to administer the cluster with kubectl
# (find yours with: az ad signed-in-user show --query id -o tsv).
cluster_admin_object_ids = [
  "2d69358a-06c0-411a-ad21-a1d044f07ed1",
]
