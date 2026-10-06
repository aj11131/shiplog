using System.Net;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Mvc;
using Shiplog.Api.Entries;

namespace Shiplog.Api.Tests;

public class EntriesApiTests : IClassFixture<ShiplogApiFactory>
{
    private readonly ShiplogApiFactory _factory;
    private readonly HttpClient _client;

    public EntriesApiTests(ShiplogApiFactory factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task Create_returns_201_with_entry_stamped_by_this_pod()
    {
        var response = await _client.PostAsJsonAsync("/api/entries", new CreateEntryRequest("  Captain ", " Anchors aweigh "));

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var entry = await response.Content.ReadFromJsonAsync<EntryResponse>();
        Assert.NotNull(entry);
        Assert.Equal("Captain", entry.Author);
        Assert.Equal("Anchors aweigh", entry.Message);
        Assert.Equal("test-cloud", entry.Cloud);
        Assert.Equal("test-cluster", entry.Cluster);
        Assert.Equal("test-pod-1", entry.Pod);
        Assert.Equal(_factory.Time.GetUtcNow().UtcDateTime, entry.CreatedAtUtc);
        Assert.Equal($"/api/entries/{entry.Id}", response.Headers.Location?.AbsolutePath);
    }

    [Fact]
    public async Task Created_entry_can_be_fetched_by_id()
    {
        var created = await CreateAsync("Bosun", "Deck swabbed");

        var fetched = await _client.GetFromJsonAsync<EntryResponse>($"/api/entries/{created.Id}");

        Assert.Equal(created, fetched);
    }

    [Fact]
    public async Task List_returns_newest_first_and_respects_limit()
    {
        var older = await CreateAsync("Navigator", "Course plotted");
        _factory.Time.Advance(TimeSpan.FromMinutes(5));
        var newer = await CreateAsync("Navigator", "Course corrected");

        var entries = await _client.GetFromJsonAsync<List<EntryResponse>>("/api/entries?limit=2");

        Assert.NotNull(entries);
        Assert.Equal(2, entries.Count);
        Assert.Equal(newer.Id, entries[0].Id);
        Assert.Equal(older.Id, entries[1].Id);
    }

    [Fact]
    public async Task Invalid_entry_returns_validation_problem()
    {
        var response = await _client.PostAsJsonAsync("/api/entries", new CreateEntryRequest("", null));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var problem = await response.Content.ReadFromJsonAsync<ValidationProblemDetails>();
        Assert.NotNull(problem);
        Assert.Contains("author", problem.Errors.Keys);
        Assert.Contains("message", problem.Errors.Keys);
    }

    [Fact]
    public async Task Delete_removes_entry_then_returns_404()
    {
        var created = await CreateAsync("Cook", "Stew's on");

        var first = await _client.DeleteAsync($"/api/entries/{created.Id}");
        var second = await _client.DeleteAsync($"/api/entries/{created.Id}");
        var get = await _client.GetAsync($"/api/entries/{created.Id}");

        Assert.Equal(HttpStatusCode.NoContent, first.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, second.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, get.StatusCode);
    }

    private async Task<EntryResponse> CreateAsync(string author, string message)
    {
        var response = await _client.PostAsJsonAsync("/api/entries", new CreateEntryRequest(author, message));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<EntryResponse>())!;
    }
}
