namespace InstallGuard.Service.Services;

public interface IAutoUpdateService
{
    Task CheckForUpdatesAsync();
    Task<bool> IsUpdateAvailableAsync();
    Task<string> GetCurrentVersionAsync();
} 