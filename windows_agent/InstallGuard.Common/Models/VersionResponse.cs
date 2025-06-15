namespace InstallGuard.Common.Models;

public class VersionResponse
{
    public string Version { get; set; } = string.Empty;
    public string Url { get; set; } = string.Empty;
}

public class VersionInfo
{
    public int Major { get; set; }
    public int Minor { get; set; }
    public int Build { get; set; }
    
    public VersionInfo(string version)
    {
        var parts = version.Split('.');
        Major = parts.Length > 0 && int.TryParse(parts[0], out var major) ? major : 0;
        Minor = parts.Length > 1 && int.TryParse(parts[1], out var minor) ? minor : 0;
        Build = parts.Length > 2 && int.TryParse(parts[2], out var build) ? build : 0;
    }
    
    public bool IsNewerThan(VersionInfo other)
    {
        if (Major > other.Major) return true;
        if (Major < other.Major) return false;
        
        if (Minor > other.Minor) return true;
        if (Minor < other.Minor) return false;
        
        return Build > other.Build;
    }
    
    public override string ToString()
    {
        return $"{Major}.{Minor}.{Build}";
    }
} 