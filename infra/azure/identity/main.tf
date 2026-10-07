# Entra ID app registrations for Shiplog.
#
#   Shiplog Web (SPA) ──signs the user in, requests a token for──► Shiplog API
#        client_id in /config.json                                   scope:    Entries.ReadWrite (what the app may do for the user)
#                                                                    app role: Shiplog.Admin     (what the user is allowed to do)
#
# Two registrations, because they are two different security principals. The SPA is a
# "public client" (code in a browser, no secret). The API is the "resource" that defines
# the permissions and validates tokens.

data "azuread_client_config" "current" {}

locals {
  # MSAL v5 returns from Entra to a "redirect bridge" page (/auth/redirect), which hands the
  # response to the app. After sign-out the user lands on the home page (/).
  origins       = concat(["https://${var.app_hostname}"], var.local_origins)
  redirect_uris = flatten([for o in local.origins : ["${o}/auth/redirect", "${o}/"]])

  # The CI apply identity owns these apps. With Application.ReadWrite.OwnedBy it can manage
  # ONLY apps it owns, and it can't add other owners: that needs Application.ReadWrite.All,
  # which can edit every app in the tenant (a classic privilege-escalation path). Global
  # Administrators can still see and manage the apps in the portal.
  owners = [data.azuread_client_config.current.object_id]
}

# Stable IDs for the scope and the role. Changing them would invalidate issued tokens and role assignments.
resource "random_uuid" "scope_entries_readwrite" {}
resource "random_uuid" "role_admin" {}

# ---------------------------------------------------------------------------
# API (resource)
# ---------------------------------------------------------------------------
resource "azuread_application" "api" {
  display_name     = "Shiplog API (${var.environment})"
  sign_in_audience = "AzureADMyOrg" # single tenant: only accounts in this directory
  owners           = local.owners

  api {
    requested_access_token_version = 2 # v2 tokens: aud = the API's client ID, iss = .../v2.0

    oauth2_permission_scope {
      id                         = random_uuid.scope_entries_readwrite.result
      value                      = "Entries.ReadWrite"
      type                       = "User" # users can consent for themselves; no admin needed
      admin_consent_display_name = "Read and write Shiplog entries"
      admin_consent_description  = "Allows the app to read and write log entries on behalf of the signed-in user."
      user_consent_display_name  = "Read and write your Shiplog entries"
      user_consent_description   = "Allows the app to read and write log entries on your behalf."
      enabled                    = true
    }
  }

  app_role {
    id                   = random_uuid.role_admin.result
    value                = "Shiplog.Admin" # appears in the token's "roles" claim
    display_name         = "Shiplog administrator"
    description          = "Can delete any log entry."
    allowed_member_types = ["User"]
    enabled              = true
  }

  lifecycle {
    # Managed by azuread_application_identifier_uri below. Without this, the two resources
    # would keep undoing each other on every apply.
    ignore_changes = [identifier_uris]
  }
}

# Identifier URI "api://<client id>": scopes are requested as api://<client id>/Entries.ReadWrite.
# It's a separate resource because it refers to the application's own client ID.
resource "azuread_application_identifier_uri" "api" {
  application_id = azuread_application.api.id
  identifier_uri = "api://${azuread_application.api.client_id}"
}

# The service principal is the API's instance in this tenant: role assignments and consent attach to it.
resource "azuread_service_principal" "api" {
  client_id = azuread_application.api.client_id
  owners    = local.owners
}

# ---------------------------------------------------------------------------
# Web (SPA client)
# ---------------------------------------------------------------------------
resource "azuread_application" "web" {
  display_name     = "Shiplog Web (${var.environment})"
  sign_in_audience = "AzureADMyOrg"
  owners           = local.owners

  # SPA platform: authorization code flow with PKCE, with no client secret.
  single_page_application {
    redirect_uris = local.redirect_uris
  }

  required_resource_access {
    resource_app_id = azuread_application.api.client_id
    resource_access {
      id   = random_uuid.scope_entries_readwrite.result
      type = "Scope"
    }
  }
}

resource "azuread_service_principal" "web" {
  client_id = azuread_application.web.client_id
  owners    = local.owners
}

# The API trusts its own SPA: users aren't asked to consent to Entries.ReadWrite.
resource "azuread_application_pre_authorized" "web" {
  application_id       = azuread_application.api.id
  authorized_client_id = azuread_application.web.client_id
  permission_ids       = [random_uuid.scope_entries_readwrite.result]
}
