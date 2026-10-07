terraform {
  required_version = ">= 1.11, < 2.0"

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.10"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }

  # Key is per environment: -backend-config="key=identity-dev.tfstate"
  backend "azurerm" {}
}

# Microsoft Graph. In CI it signs in with the same OIDC variables as azurerm (ARM_CLIENT_ID,
# ARM_TENANT_ID, ARM_USE_OIDC): plan has Application.Read.All, apply Application.ReadWrite.OwnedBy.
provider "azuread" {}
