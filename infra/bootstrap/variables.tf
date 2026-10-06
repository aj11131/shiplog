variable "subscription_id" {
  description = "Azure subscription to deploy into."
  type        = string
}

variable "location" {
  description = "Azure region for the management resources (state storage, CI identities)."
  type        = string
  default     = "centralus"
}

variable "github_repository" {
  description = "GitHub repository allowed to sign in, as OWNER/REPO."
  type        = string
  default     = "aj11131/shiplog"
}

variable "github_environment" {
  description = "GitHub environment whose jobs may use the apply identity (protected with required reviewers)."
  type        = string
  default     = "dev"
}
