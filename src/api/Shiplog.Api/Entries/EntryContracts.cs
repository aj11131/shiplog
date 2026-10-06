using Shiplog.Api.Data;

namespace Shiplog.Api.Entries;

// Author comes from the request body for now. Step 4 (Entra ID sign-in) will take it from the user's token instead.
public record CreateEntryRequest(string? Author, string? Message);

public record EntryResponse(
    Guid Id,
    string Author,
    string Message,
    DateTime CreatedAtUtc,
    string Cloud,
    string Region,
    string Cluster,
    string Node,
    string Pod)
{
    public static EntryResponse From(LogEntry e) =>
        new(e.Id, e.Author, e.Message, e.CreatedAtUtc, e.Cloud, e.Region, e.Cluster, e.Node, e.Pod);
}

public static class EntryValidator
{
    /// <summary>Returns validation errors keyed by field name; empty when the request is valid.</summary>
    public static Dictionary<string, string[]> Validate(CreateEntryRequest request)
    {
        var errors = new Dictionary<string, string[]>();

        var author = request.Author?.Trim();
        if (string.IsNullOrEmpty(author))
            errors["author"] = ["Author is required."];
        else if (author.Length > LogEntry.AuthorMaxLength)
            errors["author"] = [$"Author must be {LogEntry.AuthorMaxLength} characters or fewer."];

        var message = request.Message?.Trim();
        if (string.IsNullOrEmpty(message))
            errors["message"] = ["Message is required."];
        else if (message.Length > LogEntry.MessageMaxLength)
            errors["message"] = [$"Message must be {LogEntry.MessageMaxLength} characters or fewer."];

        return errors;
    }
}
