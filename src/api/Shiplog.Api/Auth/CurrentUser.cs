using System.Security.Claims;
using Shiplog.Api.Data;

namespace Shiplog.Api.Auth;

/// <summary>
/// The caller, as far as Shiplog cares. With auth disabled everyone is an anonymous user
/// who can do anything (local development).
/// </summary>
public record CurrentUser(
    bool AuthEnabled,
    bool IsAuthenticated,
    string? ObjectId,
    string? Name,
    IReadOnlyList<string> Roles,
    IReadOnlyList<string> Scopes)
{
    public bool IsAdmin => Roles.Contains(Auth.Roles.Admin);

    public bool CanWrite => !AuthEnabled || (IsAuthenticated && Scopes.Contains(Auth.Scopes.EntriesReadWrite));

    /// <summary>Authors may delete their own entries; Shiplog.Admin may delete any.</summary>
    public bool CanDelete(LogEntry entry) =>
        !AuthEnabled || (CanWrite && (IsAdmin || (ObjectId is not null && entry.AuthorId == ObjectId)));

    public static CurrentUser From(ClaimsPrincipal principal, AuthOptions options)
    {
        if (!options.Enabled || principal.Identity?.IsAuthenticated != true)
            return new CurrentUser(options.Enabled, false, null, null, [], []);

        return new CurrentUser(
            AuthEnabled: true,
            IsAuthenticated: true,
            // "oid": the user's immutable object ID in this tenant. Unlike names and emails, it never changes.
            ObjectId: principal.FindFirstValue("oid"),
            Name: principal.FindFirstValue("name") ?? principal.FindFirstValue("preferred_username"),
            Roles: principal.FindAll("roles").Select(c => c.Value).ToList(),
            Scopes: principal.FindAll("scp").SelectMany(c => c.Value.Split(' ', StringSplitOptions.RemoveEmptyEntries)).ToList());
    }
}
