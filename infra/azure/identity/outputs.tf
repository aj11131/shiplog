# Read by the deploy workflow. None of these are secrets: a public client's ID is visible in
# the browser anyway.

output "tenant_id" {
  value = data.azuread_client_config.current.tenant_id
}

output "app_hostname" {
  value = var.app_hostname
}

output "web_client_id" {
  value = azuread_application.web.client_id
}

output "api_client_id" {
  description = "The API validates tokens whose audience (aud) is this ID."
  value       = azuread_application.api.client_id
}

output "api_scope" {
  description = "What the SPA requests when it asks for an access token."
  value       = "api://${azuread_application.api.client_id}/Entries.ReadWrite"
}

output "admin_role" {
  value = "Shiplog.Admin"
}

# Assigning users to app roles needs AppRoleAssignment.ReadWrite.All, which CI deliberately
# doesn't have (see infra/bootstrap). A Global Administrator runs this once.
output "grant_admin_role_command" {
  value = <<-EOT
    az rest --method POST --url "https://graph.microsoft.com/v1.0/servicePrincipals/${azuread_service_principal.api.object_id}/appRoleAssignedTo" --body '{"principalId":"<YOUR-OBJECT-ID>","resourceId":"${azuread_service_principal.api.object_id}","appRoleId":"${random_uuid.role_admin.result}"}'
  EOT
}
