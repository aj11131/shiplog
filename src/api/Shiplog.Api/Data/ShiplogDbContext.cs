using Microsoft.EntityFrameworkCore;

namespace Shiplog.Api.Data;

/// <summary>
/// Provider-neutral context that the rest of the app depends on.
/// Each database provider gets its own subclass (below) so that SQLite and
/// PostgreSQL can each have their own migration history. This is the pattern
/// Microsoft documents for "multiple providers with separate migrations".
/// </summary>
public abstract class ShiplogDbContext(DbContextOptions options) : DbContext(options)
{
    public DbSet<LogEntry> LogEntries => Set<LogEntry>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<LogEntry>(entry =>
        {
            entry.HasKey(e => e.Id);
            entry.Property(e => e.Author).HasMaxLength(LogEntry.AuthorMaxLength);
            entry.Property(e => e.Message).HasMaxLength(LogEntry.MessageMaxLength);
            entry.Property(e => e.Cloud).HasMaxLength(20);
            entry.Property(e => e.Region).HasMaxLength(40);
            entry.Property(e => e.Cluster).HasMaxLength(60);
            entry.Property(e => e.Node).HasMaxLength(100);
            entry.Property(e => e.Pod).HasMaxLength(100);
            entry.HasIndex(e => e.CreatedAtUtc);
        });
    }
}

public class SqliteShiplogDbContext(DbContextOptions<SqliteShiplogDbContext> options) : ShiplogDbContext(options)
{
    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        // SQLite has no date/time type, so DateTime values come back with
        // Kind=Unspecified. Mark them as UTC so they serialize with a trailing "Z".
        modelBuilder.Entity<LogEntry>()
            .Property(e => e.CreatedAtUtc)
            .HasConversion(v => v, v => DateTime.SpecifyKind(v, DateTimeKind.Utc));
    }
}

public class PostgresShiplogDbContext(DbContextOptions<PostgresShiplogDbContext> options) : ShiplogDbContext(options);
