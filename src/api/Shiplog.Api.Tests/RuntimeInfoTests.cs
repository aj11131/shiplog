using Microsoft.Extensions.Configuration;
using Shiplog.Api.Diagnostics;

namespace Shiplog.Api.Tests;

public class RuntimeInfoTests
{
    [Fact]
    public void Defaults_describe_a_local_machine()
    {
        var info = new RuntimeInfo();

        Assert.Equal("local", info.Cloud);
        Assert.Equal(Environment.MachineName, info.Pod);
        Assert.DoesNotContain('+', info.Version);
    }

    [Fact]
    public void Binds_from_double_underscore_environment_style_keys()
    {
        // In Kubernetes these arrive as env vars like Runtime__Cloud=aks.
        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Runtime:Cloud"] = "aks",
                ["Runtime:Region"] = "eastus2",
                ["Runtime:Cluster"] = "shiplog-dev",
                ["Runtime:Node"] = "aks-system-123",
                ["Runtime:Pod"] = "shiplog-api-abc",
            })
            .Build();

        var info = config.GetSection(RuntimeInfo.SectionName).Get<RuntimeInfo>();

        Assert.NotNull(info);
        Assert.Equal("aks", info.Cloud);
        Assert.Equal("eastus2", info.Region);
        Assert.Equal("shiplog-dev", info.Cluster);
        Assert.Equal("aks-system-123", info.Node);
        Assert.Equal("shiplog-api-abc", info.Pod);
    }
}
