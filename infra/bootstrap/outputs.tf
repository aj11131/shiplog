output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  value = var.subscription_id
}

output "tfstate_resource_group" {
  value = azurerm_resource_group.mgmt.name
}

output "tfstate_storage_account" {
  value = azurerm_storage_account.tfstate.name
}

output "tfstate_container" {
  value = azurerm_storage_container.tfstate.name
}

output "plan_client_id" {
  value = module.github_plan.client_id
}

output "apply_client_id" {
  value = module.github_apply.client_id
}

# Copy-paste helper: the GitHub repository variables the workflows read.
# None of these are secrets. OIDC means there are no secrets at all.
output "github_variables_commands" {
  value = <<-EOT
    gh variable set AZURE_TENANT_ID         --body "${data.azurerm_client_config.current.tenant_id}"
    gh variable set AZURE_SUBSCRIPTION_ID   --body "${var.subscription_id}"
    gh variable set AZURE_PLAN_CLIENT_ID    --body "${module.github_plan.client_id}"
    gh variable set AZURE_APPLY_CLIENT_ID   --body "${module.github_apply.client_id}"
    gh variable set TFSTATE_RESOURCE_GROUP  --body "${azurerm_resource_group.mgmt.name}"
    gh variable set TFSTATE_STORAGE_ACCOUNT --body "${azurerm_storage_account.tfstate.name}"
  EOT
}

# Local backend config for running the other stacks from your laptop:
#   terraform init -backend-config=../../backend.local.hcl
output "backend_config" {
  value = <<-EOT
    resource_group_name  = "${azurerm_resource_group.mgmt.name}"
    storage_account_name = "${azurerm_storage_account.tfstate.name}"
    container_name       = "${azurerm_storage_container.tfstate.name}"
    use_azuread_auth     = true
  EOT
}
