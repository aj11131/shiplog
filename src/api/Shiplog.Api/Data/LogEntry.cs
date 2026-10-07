namespace Shiplog.Api.Data;

/// <summary>
/// One entry in the ship's log. Besides the user's message, every entry records
/// where it was written (cloud, cluster, node, pod) so you can see which part of
/// the infrastructure handled the request.
/// </summary>
public class LogEntry
{
    public const int AuthorMaxLength = 60;
    public const int MessageMaxLength = 280;
    public const int AuthorIdMaxLength = 64;

    public Guid Id { get; set; }
    public required string Author { get; set; }

    /// <summary>The author's Entra object ID ("oid" claim). Null for entries written with auth disabled.</summary>
    public string? AuthorId { get; set; }
    public required string Message { get; set; }
    public DateTime CreatedAtUtc { get; set; }

    // "Written by" stamp
    public required string Cloud { get; set; }
    public required string Region { get; set; }
    public required string Cluster { get; set; }
    public required string Node { get; set; }
    public required string Pod { get; set; }
}
