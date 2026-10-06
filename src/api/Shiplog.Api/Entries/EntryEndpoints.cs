using Microsoft.EntityFrameworkCore;
using Shiplog.Api.Data;
using Shiplog.Api.Diagnostics;
using Shiplog.Api.Telemetry;

namespace Shiplog.Api.Entries;

public static class EntryEndpoints
{
    public const int DefaultLimit = 50;
    public const int MaxLimit = 200;

    public static IEndpointRouteBuilder MapEntryEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/entries").WithTags("Entries");

        group.MapGet("/", async (int? limit, ShiplogDbContext db, CancellationToken ct) =>
            {
                var take = Math.Clamp(limit ?? DefaultLimit, 1, MaxLimit);
                var entries = await db.LogEntries
                    .AsNoTracking()
                    .OrderByDescending(e => e.CreatedAtUtc)
                    .Take(take)
                    .ToListAsync(ct);
                return entries.Select(EntryResponse.From);
            })
            .WithName("ListEntries");

        group.MapGet("/{id:guid}", async (Guid id, ShiplogDbContext db, CancellationToken ct) =>
                await db.LogEntries.AsNoTracking().FirstOrDefaultAsync(e => e.Id == id, ct) is { } entry
                    ? Results.Ok(EntryResponse.From(entry))
                    : Results.NotFound())
            .WithName("GetEntry");

        group.MapPost("/", async (
                CreateEntryRequest request,
                ShiplogDbContext db,
                RuntimeInfo runtime,
                TimeProvider time,
                ShiplogMetrics metrics,
                ILogger<CreateEntryRequest> logger,
                CancellationToken ct) =>
            {
                var errors = EntryValidator.Validate(request);
                if (errors.Count > 0)
                    return Results.ValidationProblem(errors);

                var entry = new LogEntry
                {
                    Id = Guid.CreateVersion7(),
                    Author = request.Author!.Trim(),
                    Message = request.Message!.Trim(),
                    CreatedAtUtc = time.GetUtcNow().UtcDateTime,
                    Cloud = runtime.Cloud,
                    Region = runtime.Region,
                    Cluster = runtime.Cluster,
                    Node = runtime.Node,
                    Pod = runtime.Pod,
                };
                db.LogEntries.Add(entry);
                await db.SaveChangesAsync(ct);

                metrics.EntryCreated();
                logger.LogInformation("Log entry {EntryId} created by {Author} on {Pod}", entry.Id, entry.Author, entry.Pod);

                return Results.CreatedAtRoute("GetEntry", new { id = entry.Id }, EntryResponse.From(entry));
            })
            .WithName("CreateEntry");

        group.MapDelete("/{id:guid}", async (
                Guid id,
                ShiplogDbContext db,
                ShiplogMetrics metrics,
                ILogger<CreateEntryRequest> logger,
                CancellationToken ct) =>
            {
                var deleted = await db.LogEntries.Where(e => e.Id == id).ExecuteDeleteAsync(ct);
                if (deleted == 0)
                    return Results.NotFound();

                metrics.EntryDeleted();
                logger.LogInformation("Log entry {EntryId} deleted", id);
                return Results.NoContent();
            })
            .WithName("DeleteEntry");

        return app;
    }
}
