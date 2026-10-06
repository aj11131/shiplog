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
  default     = "Standard_D2als_v7" # 2 vCPU / 4 GiB AMD. Check what your subscription allows: az vm list-skus -l <region> --size Standard_D2
}

variable "node_count" {
  description = "Number of nodes (the starting count when autoscaling is on)."
  type        = number
  default     = 2
}

variable "node_autoscaling" {
  description = "Cluster autoscaler bounds, e.g. { min = 2, max = 4 }. null = fixed node_count. Every node needs vCPU quota."
  type = object({
    min = number
    max = number
  })
  default = null
}

variable "node_upgrade_surge" {
  description = <<-EOT
    true:  upgrades add a temporary extra node (max_surge = 1), so capacity never drops.
    false: upgrades drain one existing node at a time (max_unavailable = 1). Needs no
           spare vCPU quota, but runs on fewer nodes during the upgrade.
  EOT
  type        = bool
  default     = false
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
