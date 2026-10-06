using System.Reflection;

namespace Shiplog.Api.Diagnostics;

/// <summary>
/// Where this API instance is running. Bound from the "Runtime" config section, so
/// in Kubernetes the Helm chart sets env vars like Runtime__Cloud=aks and fills
/// Runtime__Node / Runtime__Pod from the Downward API.
/// </summary>
public class RuntimeInfo
{
    public const string SectionName = "Runtime";

    public string Cloud { get; set; } = "local";
    public string Region { get; set; } = "local";
    public string Cluster { get; set; } = "none";
    public string Node { get; set; } = Environment.MachineName;

    // Inside Kubernetes the container hostname is the pod name, so this default is already right there.
    public string Pod { get; set; } = Environment.MachineName;

    public string Version { get; set; } = GetAppVersion();

    private static string GetAppVersion()
    {
        var version = typeof(RuntimeInfo).Assembly
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "0.0.0";

        // Drop the "+<commit sha>" build metadata the SDK appends.
        var plus = version.IndexOf('+');
        return plus >= 0 ? version[..plus] : version;
    }
}
