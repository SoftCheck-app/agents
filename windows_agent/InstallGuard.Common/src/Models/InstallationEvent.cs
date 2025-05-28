using System;

namespace InstallGuard.Common.Models
{
    public class InstallationEvent
    {
        public string EventId { get; set; } = Guid.NewGuid().ToString();
        public DateTime Timestamp { get; set; } = DateTime.Now;
        public string EventType { get; set; } = string.Empty; // Install, Uninstall, Update
        public ApplicationInfo Application { get; set; } = new ApplicationInfo();
        public string DetectionMethod { get; set; } = string.Empty; // Registry, WMI, FileSystem
        public string UserContext { get; set; } = string.Empty;
        public string SessionId { get; set; } = string.Empty;
        public bool RequiresUserNotification { get; set; } = true;
        public bool NotificationShown { get; set; } = false;
        public DateTime? NotificationShownAt { get; set; }
        public string NotificationResponse { get; set; } = string.Empty;
        public Dictionary<string, object> Metadata { get; set; } = new Dictionary<string, object>();
        public string RiskLevel { get; set; } = "Unknown"; // Low, Medium, High, Critical
        public List<string> SecurityFlags { get; set; } = new List<string>();
        public string RecommendedAction { get; set; } = string.Empty;
    }
} 