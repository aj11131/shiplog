# TFLint: catches mistakes `terraform validate` can't, e.g. invalid VM sizes or regions,
# unused declarations, and missing version constraints.
#   tflint --init --config "$(pwd)/infra/.tflint.hcl"
#   tflint --chdir=infra/azure/aks --config "$(pwd)/infra/.tflint.hcl"
config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "azurerm" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}
