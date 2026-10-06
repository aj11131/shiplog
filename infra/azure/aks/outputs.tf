# The deploy workflow reads these with `terraform output -json` to build its Helm values.

output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "cluster_name" {
  value = module.aks.name
}

output "location" {
  value = azurerm_resource_group.this.location
}

output "acr_name" {
  value = azurerm_container_registry.this.name
}

output "acr_login_server" {
  value = azurerm_container_registry.this.login_server
}

output "oidc_issuer_url" {
  value = module.aks.oidc_issuer_profile_issuer_url
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "otel_collector_client_id" {
  description = "Goes on the collector's service account (azure.workload.identity/client-id annotation)."
  value       = azurerm_user_assigned_identity.otel.client_id
}

output "otlp_endpoints" {
  value = data.terraform_remote_state.observability.outputs.otlp_endpoints
}

output "app_insights_connection_string" {
  value     = data.terraform_remote_state.observability.outputs.app_insights_connection_string
  sensitive = true
}
