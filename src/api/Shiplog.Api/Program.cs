using Shiplog.Api.Data;
using Shiplog.Api.Diagnostics;
using Shiplog.Api.Entries;
using Shiplog.Api.Telemetry;

var builder = WebApplication.CreateBuilder(args);

var runtime = builder.Configuration.GetSection(RuntimeInfo.SectionName).Get<RuntimeInfo>() ?? new RuntimeInfo();
builder.Services.AddSingleton(runtime);
builder.Services.AddSingleton(TimeProvider.System);

builder.Services.AddShiplogDatabase(builder.Configuration);
builder.Services.AddHealthChecks()
    .AddDbContextCheck<ShiplogDbContext>("database", tags: [DiagnosticsEndpoints.ReadyTag]);
builder.Services.AddProblemDetails();
builder.Services.AddOpenApi();

builder.AddShiplogTelemetry(runtime);

var app = builder.Build();

// `dotnet Shiplog.Api.dll --migrate-only` applies migrations and exits.
// The Helm chart runs this in an init container, so migrations finish before the API container starts.
if (args.Contains("--migrate-only"))
{
    await app.Services.MigrateDatabaseAsync();
    return;
}

if (app.Services.GetRequiredService<DatabaseOptions>().MigrateOnStartup)
{
    await app.Services.MigrateDatabaseAsync();
}

app.UseExceptionHandler();
app.UseStatusCodePages();
app.UseServedByHeader();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.MapEntryEndpoints();
app.MapDiagnosticsEndpoints();

app.Logger.LogInformation(
    "Shiplog API {Version} starting on {Cloud}/{Cluster}/{Pod}", runtime.Version, runtime.Cloud, runtime.Cluster, runtime.Pod);

await app.RunAsync();

// Makes Program visible to WebApplicationFactory in the test project.
public partial class Program;
