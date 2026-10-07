using System.Security.Claims;
using Microsoft.AspNetCore.Authentication.JwtBearer;

namespace Shiplog.Api.Auth;

public class AuthOptions
{
    public const string SectionName = "Auth";

    /// <summary>Off locally, on kind and in CI: anyone may write, and the author comes from the request body.</summary>
    public bool Enabled { get; set; }

    public string Instance { get; set; } = "https://login.microsoftonline.com/";
    public string TenantId { get; set; } = "";

    /// <summary>The API's client ID: Entra v2 access tokens carry it in the "aud" claim.</summary>
    public string Audience { get; set; } = "";
}

public static class Policies
{
    /// <summary>Signed in, and the token grants the app the Entries.ReadWrite scope.</summary>
    public const string Write = "entries.write";
}

public static class Scopes
{
    public const string EntriesReadWrite = "Entries.ReadWrite";
}

public static class Roles
{
    public const string Admin = "Shiplog.Admin";
}

public static class AuthExtensions
{
    public static IServiceCollection AddShiplogAuth(this IServiceCollection services, IConfiguration configuration)
    {
        var options = configuration.GetSection(AuthOptions.SectionName).Get<AuthOptions>() ?? new AuthOptions();
        services.AddSingleton(options);

        if (options.Enabled)
        {
            if (string.IsNullOrWhiteSpace(options.TenantId) || string.IsNullOrWhiteSpace(options.Audience))
                throw new InvalidOperationException("Auth:TenantId and Auth:Audience are required when Auth:Enabled is true.");

            services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
                .AddJwtBearer(jwt =>
                {
                    // The middleware downloads Entra's signing keys from
                    // {Authority}/.well-known/openid-configuration and checks each token's
                    // signature, issuer (this tenant), audience (this API) and expiry.
                    jwt.Authority = $"{options.Instance.TrimEnd('/')}/{options.TenantId}/v2.0";
                    jwt.Audience = options.Audience;

                    // Keep Entra's short claim names (oid, scp, roles, name) instead of the
                    // long legacy SOAP-style URIs ASP.NET Core would otherwise map them to.
                    jwt.MapInboundClaims = false;
                    jwt.TokenValidationParameters.NameClaimType = "name";
                    jwt.TokenValidationParameters.RoleClaimType = "roles";
                });
        }
        else
        {
            services.AddAuthentication();
        }

        services.AddAuthorization(authz =>
            authz.AddPolicy(Policies.Write, policy =>
            {
                if (options.Enabled)
                    policy.RequireAuthenticatedUser().RequireAssertion(ctx => ctx.User.HasScope(Scopes.EntriesReadWrite));
                else
                    policy.RequireAssertion(_ => true);
            }));

        return services;
    }

    /// <summary>Delegated scopes are a single space-separated "scp" claim.</summary>
    public static bool HasScope(this ClaimsPrincipal user, string scope) =>
        user.FindAll("scp").SelectMany(c => c.Value.Split(' ', StringSplitOptions.RemoveEmptyEntries)).Contains(scope);
}
