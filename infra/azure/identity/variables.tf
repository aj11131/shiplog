variable "environment" {
  description = "Environment name, used in display names."
  type        = string
  default     = "dev"
}

variable "app_hostname" {
  description = "Public HTTPS hostname of the web app (the sign-in redirect URI)."
  type        = string
}

variable "local_origins" {
  description = "Local development origins that may also sign in (plain http is only allowed for localhost)."
  type        = list(string)
  default = [
    "http://localhost:4200", # ng serve
    "http://localhost:8080", # docker compose
    "http://localhost:8090", # kind
  ]
}
