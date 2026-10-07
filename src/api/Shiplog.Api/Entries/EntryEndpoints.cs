using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using Shiplog.Api.Auth;
using Shiplog.Api.Data;
using Shiplog.Api.Diagnostics;
using Shiplog.Api.Telemetry;

namespace Shiplog.Api.Entries;

public static class EntryEndpoints
{
    public const int DefaultLimit = 50;
    public const int MaxLimit = 200;

    // Who may do what (auth enabled):
    //   GET            anyone, including anonymous callers
    //   POST           signed in, with the Entries.ReadWrite scope (policy "entries.write")
    //   DELETE         same, plus: you wrote the entry, or you hold the Shiplog.Admin app role
    // The DELETE rule depends on the entry itself ("resource-based authorization"), so it's
    // checked in the handler after loading the entry, rather than in a policy.
    public static IEndpointRouteBuilder MapEntryEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/entries").WithTags("Entries");

        group.MapGet("/", async (int? limit, ShiplogDbContext db, ClaimsPrincipal principal, AuthOptions auth, CancellationToken ct) =>
            {
                var user = CurrentUser.From(principal, auth);
                var take = Math.Clamp(limit ?? DefaultLimit, 1, MaxLimit);
                var entries = await db.LogEntries
                    .AsNoTracking()
                    .OrderByDescending(e => e.CreatedAtUtc)
                    .Take(take)
                    .ToListAsync(ct);
                return entries.Select(e => EntryResponse.From(e, user.CanDelete(e)));
            })
            .WithName("ListEntries");

        group.MapGet("/{id:guid}", async (Guid id, ShiplogDbContext db, ClaimsPrincipal principal, AuthOptions auth, CancellationToken ct) =>
                await db.LogEntries.AsNoTracking().FirstOrDefaultAsync(e => e.Id == id, ct) is { } entry
                    ? Results.Ok(EntryResponse.From(entry, CurrentUser.From(principal, auth).CanDelete(entry)))
                    : Results.NotFound())
            .WithName("GetEntry");

        group.MapPost("/", async (
                CreateEntryRequest request,
                ShiplogDbContext db,
                ClaimsPrincipal principal,
                AuthOptions auth,
                RuntimeInfo runtime,
                TimeProvider time,
                ShiplogMetrics metrics,
                ILogger<CreateEntryRequest> logger,
                CancellationToken ct) =>
            {
                var user = CurrentUser.From(principal, auth);
                var errors = EntryValidator.Validate(request, authorFromToken: user.AuthEnabled);
                if (errors.Count > 0)
                    return Results.ValidationProblem(errors);

                var author = user.AuthEnabled ? user.Name ?? "Unknown sailor" : request.Author!.Trim();
                var entry = new LogEntry
                {
                    Id = Guid.CreateVersion7(),
                    Author = author.Length > LogEntry.AuthorMaxLength ? author[..LogEntry.AuthorMaxLength] : author,
                    AuthorId = user.ObjectId,
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
                // Log the opaque object ID rather than the person's name: keep personal data out of logs.
                logger.LogInformation("Log entry {EntryId} created by {AuthorId} on {Pod}", entry.Id, entry.AuthorId ?? "anonymous", entry.Pod);

                return Results.CreatedAtRoute("GetEntry", new { id = entry.Id }, EntryResponse.From(entry, user.CanDelete(entry)));
            })
            .RequireAuthorization(Policies.Write)
            .WithName("CreateEntry");

        group.MapDelete("/{id:guid}", async (
                Guid id,
                ShiplogDbContext db,
                ClaimsPrincipal principal,
                AuthOptions auth,
                ShiplogMetrics metrics,
                ILogger<CreateEntryRequest> logger,
                CancellationToken ct) =>
            {
                var entry = await db.LogEntries.FirstOrDefaultAsync(e => e.Id == id, ct);
                if (entry is null)
                    return Results.NotFound();

                var user = CurrentUser.From(principal, auth);
                if (!user.CanDelete(entry))
                    return Results.Forbid(); // 403: you're signed in, but this isn't yours

                db.LogEntries.Remove(entry);
                await db.SaveChangesAsync(ct);

                metrics.EntryDeleted();
                logger.LogInformation("Log entry {EntryId} deleted by {UserId} (admin: {IsAdmin})", id, user.ObjectId ?? "anonymous", user.IsAdmin);
                return Results.NoContent();
            })
            .RequireAuthorization(Policies.Write)
            .WithName("DeleteEntry");

        return app;
    }
}
