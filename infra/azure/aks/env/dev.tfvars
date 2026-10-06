# Settings for the "dev" AKS environment. None of these are secrets.
# tfstate_resource_group / tfstate_storage_account come from TF_VAR_* (CI) or your local environment.
environment = "dev"
location    = "westus3" # centralus: AKSCapacityHeavyUsage (new clusters blocked for non-EA subscriptions)

# The subscription's vCPU quota in westus3 is 4 (total and per VM family), so:
#   2 nodes × 2 vCPU = 4: the whole quota. There's no room for an autoscaled node or for the
#   surge node every upgrade needs, so automatic upgrades are off (patch manually for now).
# After a quota increase (≥ 6 vCPU): auto_upgrades = true; (≥ 10): node_autoscaling = { min = 2, max = 4 }
node_vm_size     = "Standard_D2als_v7"
node_count       = 2
node_autoscaling = null
auto_upgrades    = false

# Entra ID object IDs allowed to administer the cluster with kubectl
# (find yours with: az ad signed-in-user show --query id -o tsv).
cluster_admin_object_ids = [
  "2d69358a-06c0-411a-ad21-a1d044f07ed1",
]
