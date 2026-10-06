using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace Shiplog.Api.Data;

public enum DatabaseProvider
{
    Sqlite,
    Postgres,
}

public class DatabaseOptions
{
    public const string SectionName = "Database";

    public DatabaseProvider Provider { get; set; } = DatabaseProvider.Sqlite;

    /// <summary>
    /// Apply EF Core migrations when the app starts. Handy locally; in Kubernetes
    /// an init container runs "--migrate-only" before the API starts instead.
    /// </summary>
    public bool MigrateOnStartup { get; set; }
}

public static class DatabaseExtensions
{
    public static IServiceCollection AddShiplogDatabase(this IServiceCollection services, IConfiguration configuration)
    {
        var options = configuration.GetSection(DatabaseOptions.SectionName).Get<DatabaseOptions>() ?? new DatabaseOptions();
        services.AddSingleton(options);

        var connectionString = configuration.GetConnectionString("Shiplog")
            ?? throw new InvalidOperationException("Connection string 'ConnectionStrings:Shiplog' is not configured.");

        // Endpoints depend on the abstract ShiplogDbContext; the concrete type decides the provider.
        switch (options.Provider)
        {
            case DatabaseProvider.Sqlite:
                services.AddDbContext<ShiplogDbContext, SqliteShiplogDbContext>(o => o.UseSqlite(connectionString));
                break;
            case DatabaseProvider.Postgres:
                services.AddDbContext<ShiplogDbContext, PostgresShiplogDbContext>(o => o.UseNpgsql(connectionString));
                break;
            default:
                throw new InvalidOperationException($"Unsupported database provider '{options.Provider}'.");
        }

        return services;
    }

    public static async Task MigrateDatabaseAsync(this IServiceProvider services, CancellationToken cancellationToken = default)
    {
        await using var scope = services.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<ShiplogDbContext>();
        var logger = scope.ServiceProvider.GetRequiredService<ILogger<ShiplogDbContext>>();

        var pending = (await db.Database.GetPendingMigrationsAsync(cancellationToken)).ToList();
        logger.LogInformation("Applying {PendingMigrationCount} pending migration(s): {PendingMigrations}", pending.Count, string.Join(", ", pending));
        await db.Database.MigrateAsync(cancellationToken);
    }
}

// Design-time factories are used only by the `dotnet ef` CLI when generating migrations.
// They let each provider's migrations be created without a running database.

public class SqliteDesignTimeFactory : IDesignTimeDbContextFactory<SqliteShiplogDbContext>
{
    public SqliteShiplogDbContext CreateDbContext(string[] args) =>
        new(new DbContextOptionsBuilder<SqliteShiplogDbContext>().UseSqlite("Data Source=design-time.db").Options);
}

public class PostgresDesignTimeFactory : IDesignTimeDbContextFactory<PostgresShiplogDbContext>
{
    public PostgresShiplogDbContext CreateDbContext(string[] args) =>
        new(new DbContextOptionsBuilder<PostgresShiplogDbContext>().UseNpgsql("Host=localhost;Database=shiplog").Options);
}
