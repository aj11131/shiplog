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
  default     = "Standard_D2as_v4" # 2 vCPU / 8 GiB AMD. AKS allows fewer sizes than plain VMs; the authoritative list is in the error AKS returns for a disallowed size.
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

variable "auto_upgrades" {
  description = <<-EOT
    Let AKS apply Kubernetes patch versions and node-image (OS) updates automatically.
    Every upgrade adds one surge node, so this needs vCPU quota for node_count + 1 nodes.
    Turn it off when the quota is exactly full; upgrades then become a manual task.
  EOT
  type        = bool
  default     = true
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
