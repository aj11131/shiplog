terraform {
  required_version = ">= 1.11, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.8"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.13"
    }
  }

  # Remote state in the bootstrap storage account. The account, container and key
  # (observability.tfstate) are supplied at `terraform init` time (-backend-config),
  # so the same code works locally and in CI.
  backend "azurerm" {}
}

# Both providers read ARM_SUBSCRIPTION_ID / ARM_TENANT_ID / ARM_CLIENT_ID / ARM_USE_OIDC from the environment.
provider "azurerm" {
  features {}
  resource_provider_registrations = "none" # registered once by infra/bootstrap
}

provider "azapi" {}
