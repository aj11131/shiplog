variable "name" {
  description = "Name of the managed identity."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to create the identity in."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "github_subjects" {
  description = <<-EOT
    OIDC subjects allowed to use this identity. Examples:
      repo:OWNER/REPO:pull_request        any pull request workflow
      repo:OWNER/REPO:environment:dev     jobs that target the "dev" GitHub environment
      repo:OWNER/REPO:ref:refs/heads/main pushes to main
  EOT
  type        = list(string)

  validation {
    condition     = alltrue([for s in var.github_subjects : startswith(s, "repo:")])
    error_message = "Each subject must start with \"repo:\"."
  }
}

variable "role_assignments" {
  description = <<-EOT
    Azure RBAC roles to grant the identity, keyed by a short static name (map keys must be
    known at plan time; scopes may be IDs of resources created in the same apply).
    "condition" is an optional ABAC condition (version 2.0).
  EOT
  type = map(object({
    role        = string
    scope       = string
    condition   = optional(string)
    description = optional(string)
  }))
  default = {}
}

variable "tags" {
  description = "Tags for the identity."
  type        = map(string)
  default     = {}
}
