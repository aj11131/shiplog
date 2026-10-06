locals {
  logs_host    = azapi_resource.dce.output.properties.logsIngestion.endpoint
  metrics_host = azapi_resource.dce.output.properties.metricsIngestion.endpoint
  dcr_imm_id   = azapi_resource.dcr.output.properties.immutableId
}

output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "log_analytics_workspace_id" {
  value = azapi_resource.law.id
}

output "monitor_workspace_id" {
  value = azurerm_monitor_workspace.this.id
}

output "data_collection_rule_id" {
  description = "Scope for the collector's 'Monitoring Metrics Publisher' role assignment."
  value       = azapi_resource.dcr.id
}

# Endpoint URL pattern from https://learn.microsoft.com/azure/azure-monitor/containers/opentelemetry-protocol-ingestion
output "otlp_endpoints" {
  description = "OTLP/HTTP endpoints for the OpenTelemetry Collector's otlphttp exporter."
  value = {
    traces  = "${local.logs_host}/datacollectionRules/${local.dcr_imm_id}/streams/Microsoft-OTLP-Traces/otlp/v1/traces"
    logs    = "${local.logs_host}/datacollectionRules/${local.dcr_imm_id}/streams/Microsoft-OTLP-Logs/otlp/v1/logs"
    metrics = "${local.metrics_host}/datacollectionRules/${local.dcr_imm_id}/streams/Custom-Metrics-Otel/otlp/v1/metrics"
  }
}

output "app_insights_connection_string" {
  description = "For the browser SDK. It identifies the resource rather than granting access, but treat it as sensitive anyway."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}
