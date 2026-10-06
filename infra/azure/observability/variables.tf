variable "location" {
  description = "Azure region. Keep it the same as the AKS cluster's region."
  type        = string
  default     = "centralus"
}

variable "log_retention_days" {
  description = "How long Log Analytics keeps logs and traces."
  type        = number
  default     = 30
}

variable "daily_quota_gb" {
  description = "Hard daily ingestion cap for Log Analytics. Ingestion stops for the rest of the day once it's reached (a cost safety net)."
  type        = number
  default     = 1
}
