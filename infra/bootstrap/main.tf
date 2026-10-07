# One-time bootstrap, applied from your laptop with your own `az login`:
#   1. register the Azure resource providers Shiplog uses
#   2. a storage account for Terraform remote state (Entra-only access, versioned)
#   3. two GitHub Actions identities (OIDC, no secrets):
#        plan  - read-only, usable from any pull request
#        apply - can change infrastructure, usable only from the protected "dev" environment

locals {
  tags = {
    app        = "shiplog"
    managed-by = "terraform"
    stack      = "bootstrap"
  }

  providers = toset([
    "Microsoft.AlertsManagement",
    "Microsoft.Compute",
    "Microsoft.ContainerRegistry",
    "Microsoft.ContainerService",
    "Microsoft.Insights",
    "Microsoft.ManagedIdentity",
    "Microsoft.Monitor",
    "Microsoft.Network",
    "Microsoft.OperationalInsights",
    "Microsoft.Storage",
  ])

  subscription_scope = "/subscriptions/${var.subscription_id}"

  # Built-in role IDs that the apply identity must never grant (see the ABAC condition below).
  privileged_role_ids = join(", ", [
    "8e3af657-a8ff-443c-a75c-2fe8c4bcb635", # Owner
    "18d7d88d-d35e-4fb5-a5c3-7773c20a72d9", # User Access Administrator
    "f58310d9-a9f6-439a-9e8d-f62e7b41a168", # Role Based Access Control Administrator
  ])
}

# ---------------------------------------------------------------------------
# 1. Resource providers
# ---------------------------------------------------------------------------
resource "azurerm_resource_provider_registration" "this" {
  for_each = local.providers
  name     = each.value
}

# ---------------------------------------------------------------------------
# 2. Remote state
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "mgmt" {
  name     = "rg-shiplog-mgmt"
  location = var.location
  tags     = local.tags

  depends_on = [azurerm_resource_provider_registration.this]
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_storage_account" "tfstate" {
  name                     = "stshiplogtf${random_string.suffix.result}" # globally unique, 3-24 lowercase alphanumerics
  resource_group_name      = azurerm_resource_group.mgmt.name
  location                 = azurerm_resource_group.mgmt.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  # Security: no anonymous blobs, no account keys. Every access is an Entra ID identity
  # with an RBAC role, so it is auditable and revocable.
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true

  blob_properties {
    # Every state write keeps the previous version, which lets you recover from a bad apply.
    versioning_enabled = true
    delete_retention_policy {
      days = 14
    }
    container_delete_retention_policy {
      days = 14
    }
  }

  tags = local.tags

  # Losing this account means losing every stack's state. Terraform refuses to destroy it.
  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"

  lifecycle {
    prevent_destroy = true
  }
}

# Your own user needs data-plane access too, to run `terraform init` locally against the
# remote state (being Owner isn't enough: Owner manages the account, not the blobs in it).
data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "me_tfstate" {
  scope                = azurerm_storage_container.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ---------------------------------------------------------------------------
# 3. GitHub Actions identities
# ---------------------------------------------------------------------------
module "github_plan" {
  source = "../modules/github-oidc-identity"

  name                = "id-shiplog-github-plan"
  resource_group_name = azurerm_resource_group.mgmt.name
  location            = azurerm_resource_group.mgmt.location
  tags                = local.tags

  # Any pull request in the repo may run a plan, so this identity is read-only.
  github_subjects = ["${var.github_subject_prefix}:pull_request"]

  role_assignments = {
    reader = {
      role        = "Reader"
      scope       = local.subscription_scope
      description = "terraform plan: read every resource"
    }
    state = {
      # Plan still writes: it takes a lease (lock) on the state blob.
      role        = "Storage Blob Data Contributor"
      scope       = azurerm_storage_container.tfstate.id
      description = "terraform plan: read state and take the state lock"
    }
  }
}

module "github_apply" {
  source = "../modules/github-oidc-identity"

  name                = "id-shiplog-github-apply"
  resource_group_name = azurerm_resource_group.mgmt.name
  location            = azurerm_resource_group.mgmt.location
  tags                = local.tags

  # Only jobs that declare `environment: dev`. GitHub makes them wait for a reviewer's
  # approval before they receive a token.
  github_subjects = ["${var.github_subject_prefix}:environment:${var.github_environment}"]

  role_assignments = {
    contributor = {
      role        = "Contributor"
      scope       = local.subscription_scope
      description = "terraform apply: create and change resources"
    }
    rbac = {
      # Terraform must create role assignments (e.g. AcrPull for the cluster). This role
      # allows that, and the ABAC condition stops it granting Owner, User Access
      # Administrator or RBAC Administrator, so a compromised workflow can't escalate
      # itself to full control. (This is Microsoft's documented "constrained delegation" pattern.)
      role        = "Role Based Access Control Administrator"
      scope       = local.subscription_scope
      description = "terraform apply: role assignments, excluding privileged roles"
      condition   = <<-EOT
        (
         (
          !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
         )
         OR
         (
          @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAllValues:GuidNotEquals {${local.privileged_role_ids}}
         )
        )
        AND
        (
         (
          !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
         )
         OR
         (
          @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAllValues:GuidNotEquals {${local.privileged_role_ids}}
         )
        )
      EOT
    }
    state = {
      role        = "Storage Blob Data Contributor"
      scope       = azurerm_storage_container.tfstate.id
      description = "terraform apply: read and write state"
    }
  }
}

# ---------------------------------------------------------------------------
# 4. Microsoft Graph permissions for the CI identities (step 4: Entra ID)
#
# The infra/azure/identity stack manages Shiplog's app registrations through CI.
# Graph "application permissions" are app roles on the Microsoft Graph service
# principal; assigning one IS the admin consent, which is why this runs locally
# as a Global Administrator rather than from CI.
#
# Deliberately NOT granted: AppRoleAssignment.ReadWrite.All. An identity holding it can
# grant itself any Graph permission (it's effectively tenant admin), so assigning users
# to Shiplog's app roles stays a one-time manual step (see docs/04-entra-https.md).
# ---------------------------------------------------------------------------
data "azuread_application_published_app_ids" "well_known" {}

data "azuread_service_principal" "msgraph" {
  client_id = data.azuread_application_published_app_ids.well_known.result["MicrosoftGraph"]
}

locals {
  graph_permissions = {
    # Plan reads app registrations to compare them with the code.
    plan_application_read = {
      principal = module.github_plan.principal_id
      role      = "Application.Read.All"
    }
    # Apply can create app registrations, and manage only the ones it created/owns.
    apply_application_owned = {
      principal = module.github_apply.principal_id
      role      = "Application.ReadWrite.OwnedBy"
    }
  }
}

resource "azuread_app_role_assignment" "graph" {
  for_each = local.graph_permissions

  principal_object_id = each.value.principal
  resource_object_id  = data.azuread_service_principal.msgraph.object_id
  app_role_id         = data.azuread_service_principal.msgraph.app_role_ids[each.value.role]
}
