using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Shiplog.Api.Tests;

/// <summary>
/// The API with Auth:Enabled = true, but with Entra's JWT validation swapped for a test
/// scheme. Each request describes its caller in headers. The real policies, claims handling
/// and authorization rules all run unchanged; only token *validation* is faked.
/// </summary>
public class AuthEnabledApiFactory : ShiplogApiFactory
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        base.ConfigureWebHost(builder);
        builder.UseSetting("Auth:Enabled", "true");
        builder.UseSetting("Auth:TenantId", "00000000-0000-0000-0000-000000000001");
        builder.UseSetting("Auth:Audience", "00000000-0000-0000-0000-000000000002");

        builder.ConfigureTestServices(services =>
        {
            services.AddAuthentication().AddScheme<AuthenticationSchemeOptions, TestAuthHandler>(TestAuthHandler.SchemeName, _ => { });
            services.PostConfigure<AuthenticationOptions>(o =>
            {
                o.DefaultScheme = TestAuthHandler.SchemeName;
                o.DefaultAuthenticateScheme = TestAuthHandler.SchemeName;
                o.DefaultChallengeScheme = TestAuthHandler.SchemeName;
                o.DefaultForbidScheme = TestAuthHandler.SchemeName;
            });
        });
    }
}

/// <summary>A caller as seen by the API, sent as request headers by <see cref="TestAuthHandler"/>.</summary>
public record TestUser(string ObjectId, string Name, string[]? Scopes = null, string[]? Roles = null)
{
    public static readonly string[] WriteScope = ["Entries.ReadWrite"];

    public static TestUser Alice => new("oid-alice", "Alice", WriteScope);
    public static TestUser Bob => new("oid-bob", "Bob", WriteScope);
    public static TestUser Admin => new("oid-admin", "Admiral", WriteScope, ["Shiplog.Admin"]);
    public static TestUser NoScope => new("oid-noscope", "Read Only");

    public void Apply(HttpRequestMessage request)
    {
        request.Headers.Add(TestAuthHandler.UserHeader, ObjectId);
        request.Headers.Add(TestAuthHandler.NameHeader, Name);
        if (Scopes is { Length: > 0 }) request.Headers.Add(TestAuthHandler.ScopesHeader, string.Join(' ', Scopes));
        if (Roles is { Length: > 0 }) request.Headers.Add(TestAuthHandler.RolesHeader, string.Join(',', Roles));
    }
}

public class TestAuthHandler(IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory logger, UrlEncoder encoder)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    public const string SchemeName = "Test";
    public const string UserHeader = "X-Test-Oid";
    public const string NameHeader = "X-Test-Name";
    public const string ScopesHeader = "X-Test-Scopes";
    public const string RolesHeader = "X-Test-Roles";

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        if (!Request.Headers.TryGetValue(UserHeader, out var oid))
            return Task.FromResult(AuthenticateResult.NoResult()); // anonymous

        // Same claim names as a real Entra v2 access token.
        var claims = new List<Claim> { new("oid", oid!), new("name", Request.Headers[NameHeader].ToString()) };
        if (Request.Headers.TryGetValue(ScopesHeader, out var scopes))
            claims.Add(new Claim("scp", scopes!));
        if (Request.Headers.TryGetValue(RolesHeader, out var roles))
            claims.AddRange(roles.ToString().Split(',').Select(r => new Claim("roles", r)));

        var identity = new ClaimsIdentity(claims, SchemeName, nameType: "name", roleType: "roles");
        return Task.FromResult(AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(identity), SchemeName)));
    }
}
