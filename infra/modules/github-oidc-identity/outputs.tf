output "client_id" {
  description = "Client ID to put in the workflow's azure/login step (not a secret)."
  value       = azurerm_user_assigned_identity.this.client_id
}

output "principal_id" {
  description = "Object ID of the identity's service principal, for extra role assignments."
  value       = azurerm_user_assigned_identity.this.principal_id
}

output "id" {
  description = "Resource ID of the identity."
  value       = azurerm_user_assigned_identity.this.id
}
