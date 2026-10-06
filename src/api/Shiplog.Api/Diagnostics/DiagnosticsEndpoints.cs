using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Shiplog.Api.Data;

namespace Shiplog.Api.Diagnostics;

public record DiagnosticsResponse(
    string Cloud,
    string Region,
    string Cluster,
    string Node,
    string Pod,
    string Version,
    string Environment,
    string DatabaseProvider,
    bool DatabaseReachable,
    DateTime ServerTimeUtc);

public static class DiagnosticsEndpoints
{
    public const string ServedByHeader = "X-Served-By";
    public const string ReadyTag = "ready";

    /// <summary>
    /// Adds an X-Served-By header to every response so the browser can show which pod answered.
    /// </summary>
    public static IApplicationBuilder UseServedByHeader(this IApplicationBuilder app)
    {
        var runtime = app.ApplicationServices.GetRequiredService<RuntimeInfo>();
        return app.Use((context, next) =>
        {
            context.Response.Headers[ServedByHeader] = runtime.Pod;
            return next(context);
        });
    }

    public static IEndpointRouteBuilder MapDiagnosticsEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapGet("/api/diagnostics", async (
                RuntimeInfo runtime,
                DatabaseOptions dbOptions,
                ShiplogDbContext db,
                IHostEnvironment env,
                TimeProvider time,
                CancellationToken ct) =>
            {
                var reachable = await db.Database.CanConnectAsync(ct);
                return new DiagnosticsResponse(
                    runtime.Cloud,
                    runtime.Region,
                    runtime.Cluster,
                    runtime.Node,
                    runtime.Pod,
                    runtime.Version,
                    env.EnvironmentName,
                    dbOptions.Provider.ToString(),
                    reachable,
                    time.GetUtcNow().UtcDateTime);
            })
            .WithName("GetDiagnostics")
            .WithTags("Diagnostics");

        // Kubernetes probes:
        //  - liveness:  "is the process healthy?" (no dependencies; restarting won't fix a DB outage)
        //  - readiness: "can it serve traffic?"  (includes the DB check; failing removes the pod from the Service)
        app.MapHealthChecks("/healthz/live", new HealthCheckOptions { Predicate = _ => false });
        app.MapHealthChecks("/healthz/ready", new HealthCheckOptions { Predicate = c => c.Tags.Contains(ReadyTag) });

        return app;
    }
}
