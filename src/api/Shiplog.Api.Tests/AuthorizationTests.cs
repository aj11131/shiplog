using System.Net;
using System.Net.Http.Json;
using Shiplog.Api.Auth;
using Shiplog.Api.Entries;

namespace Shiplog.Api.Tests;

/// <summary>Who may do what, with Auth:Enabled = true.</summary>
public class AuthorizationTests(AuthEnabledApiFactory factory) : IClassFixture<AuthEnabledApiFactory>
{
    private readonly HttpClient _client = factory.CreateClient();

    private async Task<HttpResponseMessage> SendAsync(HttpMethod method, string url, TestUser? user = null, object? body = null)
    {
        var request = new HttpRequestMessage(method, url);
        user?.Apply(request);
        if (body is not null)
            request.Content = JsonContent.Create(body);
        return await _client.SendAsync(request);
    }

    private async Task<EntryResponse> CreateAsAsync(TestUser user, string message)
    {
        var response = await SendAsync(HttpMethod.Post, "/api/entries", user, new CreateEntryRequest(null, message));
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return (await response.Content.ReadFromJsonAsync<EntryResponse>())!;
    }

    [Fact]
    public async Task Anyone_can_read_the_log()
    {
        var response = await SendAsync(HttpMethod.Get, "/api/entries");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task Anonymous_write_is_401()
    {
        var response = await SendAsync(HttpMethod.Post, "/api/entries", body: new CreateEntryRequest("Pirate", "Arr"));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Signed_in_without_the_scope_is_403()
    {
        var response = await SendAsync(HttpMethod.Post, "/api/entries", TestUser.NoScope, new CreateEntryRequest(null, "Hello"));

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task Author_comes_from_the_token_not_the_request_body()
    {
        var response = await SendAsync(HttpMethod.Post, "/api/entries", TestUser.Alice, new CreateEntryRequest("Captain Impersonator", "Hoist the sails"));

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var entry = await response.Content.ReadFromJsonAsync<EntryResponse>();
        Assert.Equal("Alice", entry!.Author);
        Assert.True(entry.CanDelete);
    }

    [Fact]
    public async Task Users_can_delete_their_own_entries_but_not_others()
    {
        var alices = await CreateAsAsync(TestUser.Alice, "Mine");

        var bobTries = await SendAsync(HttpMethod.Delete, $"/api/entries/{alices.Id}", TestUser.Bob);
        var aliceTries = await SendAsync(HttpMethod.Delete, $"/api/entries/{alices.Id}", TestUser.Alice);

        Assert.Equal(HttpStatusCode.Forbidden, bobTries.StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, aliceTries.StatusCode);
    }

    [Fact]
    public async Task Admins_can_delete_anyones_entry()
    {
        var alices = await CreateAsAsync(TestUser.Alice, "Admin will remove this");

        var response = await SendAsync(HttpMethod.Delete, $"/api/entries/{alices.Id}", TestUser.Admin);

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
    }

    [Fact]
    public async Task Anonymous_delete_is_401()
    {
        var alices = await CreateAsAsync(TestUser.Alice, "Still here");

        var response = await SendAsync(HttpMethod.Delete, $"/api/entries/{alices.Id}");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task CanDelete_flag_reflects_the_caller()
    {
        var alices = await CreateAsAsync(TestUser.Alice, "Whose is it?");

        async Task<bool> CanDeleteAs(TestUser? user)
        {
            var response = await SendAsync(HttpMethod.Get, $"/api/entries/{alices.Id}", user);
            return (await response.Content.ReadFromJsonAsync<EntryResponse>())!.CanDelete;
        }

        Assert.True(await CanDeleteAs(TestUser.Alice));
        Assert.False(await CanDeleteAs(TestUser.Bob));
        Assert.True(await CanDeleteAs(TestUser.Admin));
        Assert.False(await CanDeleteAs(null));
    }

    [Fact]
    public async Task Me_shows_what_the_api_sees_in_the_token()
    {
        var anonymous = await (await SendAsync(HttpMethod.Get, "/api/me")).Content.ReadFromJsonAsync<MeResponse>();
        var admin = await (await SendAsync(HttpMethod.Get, "/api/me", TestUser.Admin)).Content.ReadFromJsonAsync<MeResponse>();

        Assert.True(anonymous!.AuthEnabled);
        Assert.False(anonymous.IsAuthenticated);
        Assert.False(anonymous.CanWrite);

        Assert.True(admin!.IsAuthenticated);
        Assert.Equal("Admiral", admin.Name);
        Assert.Equal("oid-admin", admin.ObjectId);
        Assert.Equal(["Shiplog.Admin"], admin.Roles);
        Assert.Equal(["Entries.ReadWrite"], admin.Scopes);
        Assert.True(admin.IsAdmin);
        Assert.True(admin.CanWrite);
    }
}
