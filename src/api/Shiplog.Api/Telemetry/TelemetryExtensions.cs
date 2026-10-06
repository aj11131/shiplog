using OpenTelemetry;
using OpenTelemetry.Logs;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using Shiplog.Api.Diagnostics;

namespace Shiplog.Api.Telemetry;

public static class TelemetryExtensions
{
    public const string ServiceName = "shiplog-api";

    /// <summary>
    /// Wires up OpenTelemetry traces, metrics and logs.
    ///
    /// The app only knows how to speak OTLP. Where the data ends up is decided by
    /// whoever receives it: the Aspire dashboard locally, and an OpenTelemetry
    /// Collector in the cluster (which forwards to Azure Monitor). Export is enabled
    /// only when OTEL_EXPORTER_OTLP_ENDPOINT is set.
    /// </summary>
    public static WebApplicationBuilder AddShiplogTelemetry(this WebApplicationBuilder builder, RuntimeInfo runtime)
    {
        builder.Services.AddSingleton<ShiplogMetrics>();

        builder.Logging.AddOpenTelemetry(logging =>
        {
            logging.IncludeFormattedMessage = true;
            logging.IncludeScopes = true;
        });

        var otel = builder.Services.AddOpenTelemetry()
            .ConfigureResource(resource => resource
                .AddService(ServiceName, serviceVersion: runtime.Version)
                // Semantic-convention attributes, so every signal says where it came from.
                .AddAttributes(new Dictionary<string, object>
                {
                    ["cloud.provider"] = runtime.Cloud,
                    ["cloud.region"] = runtime.Region,
                    ["k8s.cluster.name"] = runtime.Cluster,
                    ["k8s.node.name"] = runtime.Node,
                    ["k8s.pod.name"] = runtime.Pod,
                    ["deployment.environment.name"] = builder.Environment.EnvironmentName,
                }))
            .WithTracing(tracing => tracing
                .AddAspNetCoreInstrumentation(o =>
                {
                    // Probe traffic would otherwise dominate the traces.
                    o.Filter = ctx => !ctx.Request.Path.StartsWithSegments("/healthz");
                })
                .AddHttpClientInstrumentation()
                .AddEntityFrameworkCoreInstrumentation())
            .WithMetrics(metrics => metrics
                .AddAspNetCoreInstrumentation()
                .AddHttpClientInstrumentation()
                .AddRuntimeInstrumentation()
                .AddMeter(ShiplogMetrics.MeterName));

        if (!string.IsNullOrWhiteSpace(builder.Configuration["OTEL_EXPORTER_OTLP_ENDPOINT"]))
        {
            otel.UseOtlpExporter();
        }

        return builder;
    }
}
