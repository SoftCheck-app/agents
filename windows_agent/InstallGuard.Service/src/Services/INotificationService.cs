using InstallGuard.Common.Models;

namespace InstallGuard.Service.Services
{
    public interface INotificationService
    {
        Task ShowInstallationNotificationAsync(InstallationEvent installationEvent);
        Task ShowCustomNotificationAsync(string title, string message, string iconType = "Info");
        Task<bool> IsUserSessionActiveAsync();
        bool IsNotificationServiceAvailable { get; }
    }
} 