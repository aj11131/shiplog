# A user-assigned managed identity that GitHub Actions can sign in as, using OIDC
# federation: no client secret exists anywhere.
#
# How it works: a workflow asks GitHub for a short-lived OIDC token whose "subject"
# describes where it's running (e.g. repo:owner/repo:environment:dev). Azure trusts the
# token only if the subject exactly matches one of the federated credentials below.

terraform {
  required_version = ">= 1.11"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.0"
    }
  }
}

resource "azurerm_user_assigned_identity" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "github" {
  for_each = toset(var.github_subjects)

  # Names may not contain ':' or '/', so derive one from the subject.
  name                      = substr(replace(replace(each.value, ":", "-"), "/", "-"), 0, 120)
  user_assigned_identity_id = azurerm_user_assigned_identity.this.id
  issuer                    = "https://token.actions.githubusercontent.com"
  audience                  = ["api://AzureADTokenExchange"]
  subject                   = each.value
}

resource "azurerm_role_assignment" "this" {
  for_each = var.role_assignments

  principal_id         = azurerm_user_assigned_identity.this.principal_id
  principal_type       = "ServicePrincipal"
  scope                = each.value.scope
  role_definition_name = each.value.role
  condition            = each.value.condition
  condition_version    = each.value.condition == null ? null : "2.0"
  description          = each.value.description
}
