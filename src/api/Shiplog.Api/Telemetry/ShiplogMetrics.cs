using System.Diagnostics.Metrics;
using Shiplog.Api.Diagnostics;

namespace Shiplog.Api.Telemetry;

/// <summary>
/// Custom business metrics, exported through OpenTelemetry alongside the built-in
/// ASP.NET Core and runtime metrics.
/// </summary>
public class ShiplogMetrics
{
    public const string MeterName = "Shiplog.Api";

    private readonly Counter<long> _entriesCreated;
    private readonly Counter<long> _entriesDeleted;
    private readonly KeyValuePair<string, object?> _cloudTag;

    public ShiplogMetrics(IMeterFactory meterFactory, RuntimeInfo runtime)
    {
        var meter = meterFactory.Create(MeterName);
        _entriesCreated = meter.CreateCounter<long>("shiplog.entries.created", unit: "{entry}", description: "Log entries created");
        _entriesDeleted = meter.CreateCounter<long>("shiplog.entries.deleted", unit: "{entry}", description: "Log entries deleted");
        _cloudTag = new("shiplog.cloud", runtime.Cloud);
    }

    public void EntryCreated() => _entriesCreated.Add(1, _cloudTag);

    public void EntryDeleted() => _entriesDeleted.Add(1, _cloudTag);
}
