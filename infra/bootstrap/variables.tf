variable "subscription_id" {
  description = "Azure subscription to deploy into."
  type        = string
}

variable "location" {
  description = "Azure region for the management resources (state storage, CI identities)."
  type        = string
  default     = "centralus"
}

variable "github_subject_prefix" {
  description = <<-EOT
    Start of the OIDC subject GitHub puts in this repo's tokens. With immutable subjects
    (GitHub's default for new repos) it includes the owner and repo IDs, so a renamed or
    re-created repo with the same name can't match. Read the exact value with:
      gh api repos/OWNER/REPO/actions/oidc/customization/sub --jq .sub_claim_prefix
  EOT
  type        = string
  default     = "repo:aj11131@54563379/shiplog@1407845180"

  validation {
    condition     = startswith(var.github_subject_prefix, "repo:")
    error_message = "The prefix must start with \"repo:\"."
  }
}

variable "github_environment" {
  description = "GitHub environment whose jobs may use the apply identity (protected with required reviewers)."
  type        = string
  default     = "dev"
}
