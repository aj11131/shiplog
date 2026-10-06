variable "environment" {
  description = "Environment name, used in resource names (rg-shiplog-<env>-aks, aks-shiplog-<env>)."
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "centralus"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version (e.g. \"1.34\"). null = the region's current default."
  type        = string
  default     = null
}

variable "node_vm_size" {
  description = "VM size for the node pool."
  type        = string
  default     = "Standard_B2als_v2" # 2 vCPU / 4 GiB burstable; cheap, fine for a test cluster
}

variable "node_min_count" {
  description = "Minimum nodes (cluster autoscaler)."
  type        = number
  default     = 2
}

variable "node_max_count" {
  description = "Maximum nodes (cluster autoscaler)."
  type        = number
  default     = 3
}

variable "cluster_admin_object_ids" {
  description = "Entra ID object IDs (users or groups) granted 'Azure Kubernetes Service RBAC Cluster Admin'."
  type        = list(string)
  default     = []
}

variable "tfstate_resource_group" {
  description = "Resource group of the Terraform state account (from infra/bootstrap)."
  type        = string
}

variable "tfstate_storage_account" {
  description = "Terraform state storage account (from infra/bootstrap)."
  type        = string
}

variable "deployer_identity_name" {
  description = "Managed identity that GitHub Actions uses to deploy (created by infra/bootstrap)."
  type        = string
  default     = "id-shiplog-github-apply"
}

variable "otel_namespace" {
  description = "Kubernetes namespace of the OpenTelemetry Collector."
  type        = string
  default     = "observability"
}

variable "otel_service_account" {
  description = "Kubernetes service account of the OpenTelemetry Collector."
  type        = string
  default     = "otel-collector"
}
