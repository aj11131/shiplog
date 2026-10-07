terraform {
  required_version = ">= 1.11, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.8"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.10"
    }
  }

  # Deliberately LOCAL state. Bootstrap creates the remote-state storage account itself,
  # so it can't store its own state there (chicken-and-egg). terraform.tfstate is
  # gitignored. Keep it, or re-import if it's lost; see docs/03-aks-terraform.md.
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id

  # Register exactly the providers we need (below) rather than letting Terraform
  # register a large default set. CI stacks set this to "none" too, so the read-only
  # plan identity never attempts a registration.
  resource_provider_registrations = "none"

  # The state storage account has shared-key (access key) auth disabled, so the data
  # plane (creating the container) must use Entra ID.
  storage_use_azuread = true
}

# Microsoft Graph (Entra ID). Locally it authenticates as your az login.
provider "azuread" {}
