using SoftCheck.Common.Models;

namespace SoftCheck.Service.Services
{
    public interface IInstallationMonitorService
    {
        Task StartMonitoringAsync(CancellationToken cancellationToken);
        Task StopMonitoringAsync();
        event EventHandler<InstallationEvent> InstallationDetected;
        Task<List<ApplicationInfo>> GetInstalledApplicationsAsync();
        Task<ApplicationInfo?> GetApplicationInfoAsync(string registryKey);
        bool IsMonitoring { get; }
    }
} 
