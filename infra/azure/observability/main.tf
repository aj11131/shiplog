# Shared observability backend for every Shiplog cluster (AKS now, EKS in step 5).
# It lives in its own state, so destroying or switching clusters keeps the history.
#
#   apps (OTLP) ──► OTel Collector in the cluster ──► Data Collection Endpoint/Rule ──┬─► Log Analytics  (logs, traces)
#                    (authenticates with Entra ID)                                   └─► Azure Monitor workspace (metrics)
#   browser ──► Application Insights JS SDK ──► Application Insights (same Log Analytics workspace)

locals {
  tags = {
    app        = "shiplog"
    managed-by = "terraform"
    stack      = "observability"
  }
}

resource "azurerm_resource_group" "this" {
  name     = "rg-shiplog-observability"
  location = var.location
  tags     = local.tags
}

# Log Analytics is created through azapi rather than azurerm on purpose: azurerm's read
# also fetches the workspace's shared keys, which the read-only CI plan identity can't do.
resource "azapi_resource" "law" {
  type      = "Microsoft.OperationalInsights/workspaces@2023-09-01"
  name      = "log-shiplog"
  parent_id = azurerm_resource_group.this.id
  location  = azurerm_resource_group.this.location
  tags      = local.tags

  body = {
    properties = {
      sku             = { name = "PerGB2018" } # pay per GB (the first 5 GB/month per billing account are free)
      retentionInDays = var.log_retention_days
      workspaceCapping = {
        dailyQuotaGb = var.daily_quota_gb
      }
      features = {
        # No shared-key ingestion. Data arrives only through Entra-authenticated paths (DCRs).
        disableLocalAuth = true
      }
    }
  }

  response_export_values = ["properties.customerId"]
}

resource "azurerm_application_insights" "this" {
  name                = "appi-shiplog"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  application_type    = "web"
  workspace_id        = azapi_resource.law.id
  tags                = local.tags

  # The browser JS SDK can only authenticate with the connection string (instrumentation
  # key); browsers can't obtain Entra tokens for ingestion. So local auth stays on for the
  # web client, while server-side telemetry goes through the Entra-only DCR path below.
  local_authentication_enabled = true
}

# Prometheus-compatible metrics store (also known as "managed Prometheus").
resource "azurerm_monitor_workspace" "this" {
  name                = "amw-shiplog"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# OTLP ingestion: a Data Collection Endpoint (the URL) and a Data Collection Rule
# (which streams are accepted and where they go). Translated from Microsoft's template:
# https://github.com/microsoft/AzureMonitorCommunity/tree/master/Azure%20Services/Azure%20Monitor/OpenTelemetry
# azapi is used because azurerm doesn't model the new OTLP data source types yet.
# ---------------------------------------------------------------------------
resource "azapi_resource" "dce" {
  type      = "Microsoft.Insights/dataCollectionEndpoints@2024-03-11"
  name      = "dce-shiplog-otlp"
  parent_id = azurerm_resource_group.this.id
  location  = azurerm_resource_group.this.location
  tags      = local.tags

  body = {
    properties = {
      description = "OTLP ingestion endpoint for Shiplog clusters"
      networkAcls = { publicNetworkAccess = "Enabled" }
    }
  }

  response_export_values = ["properties.logsIngestion.endpoint", "properties.metricsIngestion.endpoint"]
}

locals {
  otel_common = {
    enrichWithResourceAttributes = ["*"]
    enrichWithReference          = "appInsights"
  }
  trace_streams = ["Microsoft-OTel-Traces-Spans", "Microsoft-OTel-Traces-Events", "Microsoft-OTel-Traces-Resources"]
}

resource "azapi_resource" "dcr" {
  type      = "Microsoft.Insights/dataCollectionRules@2024-03-11"
  name      = "dcr-shiplog-otlp"
  parent_id = azurerm_resource_group.this.id
  location  = azurerm_resource_group.this.location
  tags      = local.tags

  body = {
    properties = {
      description              = "OTLP traces/logs to Log Analytics, metrics to the Azure Monitor workspace"
      dataCollectionEndpointId = azapi_resource.dce.id

      # Links the data to Application Insights, so it appears in its Application Map, Failures, etc.
      references = {
        applicationInsights = [{ resourceId = azurerm_application_insights.this.id, name = "appInsights" }]
      }

      # "direct" = sent straight to the endpoint by an OpenTelemetry Collector (our case).
      directDataSources = {
        otelMetrics = [merge(local.otel_common, { name = "otelMetrics", streams = ["Custom-Metrics-Otel"] })]
        otelLogs    = [merge(local.otel_common, { name = "otelLogs", streams = ["Microsoft-OTel-Logs"], replaceResourceIdWithReference = true })]
        otelTraces  = [merge(local.otel_common, { name = "otelTraces", streams = local.trace_streams, replaceResourceIdWithReference = true })]
      }

      destinations = {
        monitoringAccounts = [{ accountResourceId = azurerm_monitor_workspace.this.id, name = "amw" }]
        logAnalytics       = [{ workspaceResourceId = azapi_resource.law.id, name = "law" }]
      }

      dataFlows = [
        { streams = ["Custom-Metrics-Otel"], destinations = ["amw"] },
        { streams = concat(["Microsoft-OTel-Logs"], local.trace_streams), destinations = ["law"] },
      ]
    }
  }

  response_export_values = ["properties.immutableId"]
}
