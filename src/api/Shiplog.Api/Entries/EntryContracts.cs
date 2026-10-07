using Shiplog.Api.Data;

namespace Shiplog.Api.Entries;

/// <summary>
/// With auth enabled, Author is ignored: the name comes from the signed-in user's token, so
/// nobody can post as someone else. With auth disabled (local dev), the caller supplies it.
/// </summary>
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
    string Pod,
    bool CanDelete)
{
    public static EntryResponse From(LogEntry e, bool canDelete) =>
        new(e.Id, e.Author, e.Message, e.CreatedAtUtc, e.Cloud, e.Region, e.Cluster, e.Node, e.Pod, canDelete);
}

public static class EntryValidator
{
    /// <summary>Returns validation errors keyed by field name; empty when the request is valid.</summary>
    /// <param name="authorFromToken">True when the author comes from the token, so the body's Author isn't checked.</param>
    public static Dictionary<string, string[]> Validate(CreateEntryRequest request, bool authorFromToken = false)
    {
        var errors = new Dictionary<string, string[]>();

        if (!authorFromToken)
        {
            var author = request.Author?.Trim();
            if (string.IsNullOrEmpty(author))
                errors["author"] = ["Author is required."];
            else if (author.Length > LogEntry.AuthorMaxLength)
                errors["author"] = [$"Author must be {LogEntry.AuthorMaxLength} characters or fewer."];
        }

        var message = request.Message?.Trim();
        if (string.IsNullOrEmpty(message))
            errors["message"] = ["Message is required."];
        else if (message.Length > LogEntry.MessageMaxLength)
            errors["message"] = [$"Message must be {LogEntry.MessageMaxLength} characters or fewer."];

        return errors;
    }
}
