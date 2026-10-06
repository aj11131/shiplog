using Shiplog.Api.Entries;

namespace Shiplog.Api.Tests;

public class EntryValidatorTests
{
    [Fact]
    public void Valid_request_has_no_errors()
    {
        var errors = EntryValidator.Validate(new CreateEntryRequest("Captain", "Land ho!"));

        Assert.Empty(errors);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void Missing_author_is_rejected(string? author)
    {
        var errors = EntryValidator.Validate(new CreateEntryRequest(author, "Land ho!"));

        Assert.Equal(["author"], errors.Keys);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("\t\n")]
    public void Missing_message_is_rejected(string? message)
    {
        var errors = EntryValidator.Validate(new CreateEntryRequest("Captain", message));

        Assert.Equal(["message"], errors.Keys);
    }

    [Fact]
    public void Too_long_fields_are_rejected()
    {
        var errors = EntryValidator.Validate(new CreateEntryRequest(new string('a', 61), new string('m', 281)));

        Assert.Contains("author", errors.Keys);
        Assert.Contains("message", errors.Keys);
    }

    [Fact]
    public void Length_limits_apply_after_trimming()
    {
        var errors = EntryValidator.Validate(new CreateEntryRequest($"  {new string('a', 60)}  ", $" {new string('m', 280)} "));

        Assert.Empty(errors);
    }
}
