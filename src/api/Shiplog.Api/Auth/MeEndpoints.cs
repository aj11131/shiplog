using System.Security.Claims;

namespace Shiplog.Api.Auth;

public record MeResponse(
    bool AuthEnabled,
    bool IsAuthenticated,
    string? Name,
    string? ObjectId,
    IReadOnlyList<string> Roles,
    IReadOnlyList<string> Scopes,
    bool IsAdmin,
    bool CanWrite);

public static class MeEndpoints
{
    /// <summary>What the API sees in your token. Anonymous calls are allowed (they just show "not signed in").</summary>
    public static IEndpointRouteBuilder MapMeEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapGet("/api/me", (ClaimsPrincipal principal, AuthOptions options) =>
            {
                var user = CurrentUser.From(principal, options);
                return new MeResponse(
                    user.AuthEnabled, user.IsAuthenticated, user.Name, user.ObjectId,
                    user.Roles, user.Scopes, user.IsAdmin, user.CanWrite);
            })
            .WithName("GetMe")
            .WithTags("Auth");

        return app;
    }
}
