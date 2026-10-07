using System.Net;
using System.Net.Http.Json;
using Shiplog.Api.Diagnostics;

namespace Shiplog.Api.Tests;

public class DiagnosticsApiTests(ShiplogApiFactory factory) : IClassFixture<ShiplogApiFactory>
{
    private readonly HttpClient _client = factory.CreateClient();

    [Fact]
    public async Task Diagnostics_reports_runtime_and_database()
    {
        var diagnostics = await _client.GetFromJsonAsync<DiagnosticsResponse>("/api/diagnostics");

        Assert.NotNull(diagnostics);
        Assert.Equal("test-cloud", diagnostics.Cloud);
        Assert.Equal("test-pod-1", diagnostics.Pod);
        Assert.Equal("Sqlite", diagnostics.DatabaseProvider);
        Assert.True(diagnostics.DatabaseReachable);
        Assert.Equal("Testing", diagnostics.Environment);
    }

    [Theory]
    [InlineData("/healthz/live")]
    [InlineData("/healthz/ready")]
    public async Task Health_endpoints_are_healthy(string path)
    {
        var response = await _client.GetAsync(path);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("Healthy", await response.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task Me_reports_auth_disabled_and_full_access()
    {
        var me = await _client.GetFromJsonAsync<Shiplog.Api.Auth.MeResponse>("/api/me");

        Assert.NotNull(me);
        Assert.False(me.AuthEnabled);
        Assert.True(me.CanWrite);
    }

    [Fact]
    public async Task Every_response_says_which_pod_served_it()
    {
        var response = await _client.GetAsync("/api/entries");

        Assert.Equal("test-pod-1", response.Headers.GetValues(DiagnosticsEndpoints.ServedByHeader).Single());
    }
}
