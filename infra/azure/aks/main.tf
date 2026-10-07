# AKS cluster for Shiplog, plus everything it needs to pull images and send telemetry.
#
#   ACR ──(AcrPull, kubelet identity)──► AKS ◄──(RBAC Cluster Admin)── you, GitHub deploy identity
#                                         │
#                      OTel Collector pod ─(Workload Identity: federated credential)─► Monitoring Metrics Publisher on the DCR

locals {
  name = "shiplog-${var.environment}"
  tags = {
    app         = "shiplog"
    environment = var.environment
    managed-by  = "terraform"
    stack       = "aks"
  }
}

data "azurerm_client_config" "current" {}

# Outputs of the observability stack (DCR, endpoints, App Insights), read from its state file.
data "terraform_remote_state" "observability" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.tfstate_resource_group
    storage_account_name = var.tfstate_storage_account
    container_name       = "tfstate"
    key                  = "observability.tfstate"
    use_azuread_auth     = true
  }

  # Used while the observability stack hasn't been applied yet (e.g. the very first PR,
  # where both stacks are only planned). Its pieces are then simply left out of the plan.
  defaults = {
    data_collection_rule_id        = null
    otlp_endpoints                 = null
    app_insights_connection_string = null
  }
}

locals {
  observability_ready = data.terraform_remote_state.observability.outputs.data_collection_rule_id != null
}

check "observability_applied" {
  assert {
    condition     = local.observability_ready
    error_message = "The observability stack has no state yet, so the collector's DCR role assignment is skipped in this plan. Apply infra/azure/observability first (the apply workflow does this automatically)."
  }
}

# The GitHub Actions identity that deploys with Helm (created by infra/bootstrap).
data "azurerm_user_assigned_identity" "deployer" {
  name                = var.deployer_identity_name
  resource_group_name = var.tfstate_resource_group
}

# The region is part of the name. The AKS module marks a resource create_before_destroy,
# and Terraform propagates that to everything the resource depends on, including this
# group. So moving regions creates the NEW group before deleting the old one, which only
# works if the two names differ.
resource "azurerm_resource_group" "this" {
  name     = "rg-${local.name}-aks-${var.location}"
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------------------
# Container registry
# ---------------------------------------------------------------------------
resource "random_string" "acr_suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_container_registry" "this" {
  name                = "crshiplog${random_string.acr_suffix.result}" # globally unique, alphanumeric only
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "Basic"
  admin_enabled       = false # no username/password; pulls and pushes use Entra identities
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# AKS: Azure Verified Module (Microsoft's official module)
# https://registry.terraform.io/modules/Azure/avm-res-containerservice-managedcluster/azurerm
# ---------------------------------------------------------------------------
module "aks" {
  source  = "Azure/avm-res-containerservice-managedcluster/azurerm"
  version = "0.8.3"

  name                = "aks-${local.name}"
  location            = azurerm_resource_group.this.location
  parent_id           = azurerm_resource_group.this.id
  dns_prefix          = "aks-${local.name}"
  node_resource_group = "rg-${local.name}-aks-${var.location}-nodes" # where AKS puts the VMs, disks, load balancer
  kubernetes_version  = var.kubernetes_version
  enable_telemetry    = false # don't send AVM usage telemetry to Microsoft
  tags                = local.tags

  # Free tier: no uptime SLA and no control-plane charge. "Standard" adds the SLA (about $73/month).
  sku = { name = "Base", tier = "Free" }

  # --- Identity & access ---------------------------------------------------
  # kubectl sign-in goes through Entra ID, and authorization uses Azure RBAC roles
  # (assigned below) instead of Kubernetes RoleBindings. With local accounts disabled
  # there is no static admin kubeconfig to leak.
  managed_identities = { system_assigned = true }
  aad_profile = {
    managed           = true
    enable_azure_rbac = true
    tenant_id         = data.azurerm_client_config.current.tenant_id
  }
  disable_local_accounts = true

  # Workload Identity: pods exchange their Kubernetes service account token (signed by
  # this OIDC issuer) for an Entra token, so pods never hold Azure credentials.
  oidc_issuer_profile = { enabled = true }
  security_profile = {
    workload_identity = { enabled = true }
    image_cleaner     = { enabled = true, interval_hours = 168 } # weekly removal of unused images from nodes
  }

  # --- Networking ----------------------------------------------------------
  # Azure CNI Overlay: pods get IPs from a private overlay range (not your VNet), so you
  # don't have to plan pod subnet sizes. Cilium (eBPF) is the dataplane and also enforces
  # the chart's NetworkPolicies.
  network_profile = {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_dataplane   = "cilium"
    network_policy      = "cilium"
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }

  # --- Nodes ---------------------------------------------------------------
  # One pool that runs both system pods and the app (cheapest). Production clusters
  # usually separate them into system and user pools.
  default_agent_pool = {
    name                = "system"
    mode                = "System"
    vm_size             = var.node_vm_size
    os_sku              = "AzureLinux"
    count_of            = var.node_count
    enable_auto_scaling = var.node_autoscaling != null
    min_count           = try(var.node_autoscaling.min, null)
    max_count           = try(var.node_autoscaling.max, null)

    # Upgrades add one temporary node, move pods onto it, then replace the old nodes one
    # by one. System pools must surge: AKS rejects max_unavailable > 0 for them. The
    # surge node needs spare vCPU quota (see var.auto_upgrades).
    upgrade_settings = { max_surge = "1" }
  }

  # --- Ingress: Gateway API ---------------------------------------------------
  # AKS installs and upgrades the Gateway API CRDs ("Standard" channel) and runs a managed,
  # sidecar-free Istio control plane that turns our Gateway resources into Envoy proxies
  # behind an Azure load balancer (GatewayClass "approuting-istio"). This is the supported
  # successor to the managed NGINX ingress, which loses support in November 2026.
  ingress_profile = {
    gateway_api = { installation = "Standard" }
    web_app_routing = {
      gateway_api_implementations = {
        app_routing_istio = { mode = "Enabled" }
      }
    }
  }

  # On: patch-version Kubernetes upgrades and weekly node-image updates, applied automatically.
  # Off: nothing is upgraded until you trigger it (az aks upgrade / az aks nodepool upgrade --node-image-only).
  auto_upgrade_profile = var.auto_upgrades ? {
    upgrade_channel         = "patch"
    node_os_upgrade_channel = "NodeImage"
    } : {
    upgrade_channel         = "none"
    node_os_upgrade_channel = "None"
  }
}

# ---------------------------------------------------------------------------
# Role assignments
# ---------------------------------------------------------------------------

# Nodes (kubelet identity) pull images from ACR, so no imagePullSecrets are needed.
resource "azurerm_role_assignment" "kubelet_acr_pull" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = module.aks.kubelet_identity.objectId
  principal_type       = "ServicePrincipal"

  # The AVM module's outputs become "(known after apply)" whenever the cluster has ANY
  # in-place change (e.g. enabling Gateway API), which would make Terraform needlessly
  # REPLACE this assignment and briefly break image pulls. The kubelet identity is fixed
  # for the cluster's lifetime; destroying the cluster destroys this resource too.
  lifecycle {
    ignore_changes = [principal_id]
  }
}

# Humans who may administer the cluster with kubectl.
resource "azurerm_role_assignment" "cluster_admins" {
  for_each = toset(var.cluster_admin_object_ids)

  scope                = module.aks.resource_id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = each.value
}

# GitHub Actions: push images, then deploy with Helm (the collector chart creates cluster-scoped RBAC, so it needs Cluster Admin).
resource "azurerm_role_assignment" "deployer_acr_push" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPush"
  principal_id         = data.azurerm_user_assigned_identity.deployer.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "deployer_cluster_admin" {
  scope                = module.aks.resource_id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azurerm_user_assigned_identity.deployer.principal_id
  principal_type       = "ServicePrincipal"
}

# ---------------------------------------------------------------------------
# Workload Identity for the OpenTelemetry Collector
# ---------------------------------------------------------------------------
resource "azurerm_user_assigned_identity" "otel" {
  name                = "id-${local.name}-otel-collector"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
}

# "Trust tokens from THIS cluster, for THIS service account only."
resource "azurerm_federated_identity_credential" "otel" {
  name                      = "aks-${local.name}-${var.otel_namespace}-${var.otel_service_account}"
  user_assigned_identity_id = azurerm_user_assigned_identity.otel.id
  issuer                    = module.aks.oidc_issuer_profile_issuer_url
  audience                  = ["api://AzureADTokenExchange"]
  subject                   = "system:serviceaccount:${var.otel_namespace}:${var.otel_service_account}"

  # Same reason as kubelet_acr_pull: the issuer URL is fixed for the cluster's lifetime.
  lifecycle {
    ignore_changes = [issuer]
  }
}

# The only permission the collector has: write telemetry through this one Data Collection Rule.
resource "azurerm_role_assignment" "otel_dcr" {
  count = local.observability_ready ? 1 : 0

  scope                = data.terraform_remote_state.observability.outputs.data_collection_rule_id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azurerm_user_assigned_identity.otel.principal_id
  principal_type       = "ServicePrincipal"
}
