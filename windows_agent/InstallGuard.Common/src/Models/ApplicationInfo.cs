using System;

namespace InstallGuard.Common.Models
{
    public class ApplicationInfo
    {
        public string Name { get; set; } = string.Empty;
        public string Version { get; set; } = string.Empty;
        public string Publisher { get; set; } = string.Empty;
        public string InstallLocation { get; set; } = string.Empty;
        public string InstallDate { get; set; } = string.Empty;
        public string UninstallString { get; set; } = string.Empty;
        public string DisplayIcon { get; set; } = string.Empty;
        public string EstimatedSize { get; set; } = string.Empty;
        public string ProductCode { get; set; } = string.Empty;
        public string RegistryKey { get; set; } = string.Empty;
        public DateTime DetectedAt { get; set; } = DateTime.Now;
        public string Description { get; set; } = string.Empty;
        public string HelpLink { get; set; } = string.Empty;
        public string URLInfoAbout { get; set; } = string.Empty;
        public string Contact { get; set; } = string.Empty;
        public bool IsSystemComponent { get; set; } = false;
        public string Architecture { get; set; } = string.Empty;
        public string Language { get; set; } = string.Empty;
        public string InstallSource { get; set; } = string.Empty;
        public string ModifyPath { get; set; } = string.Empty;
        public bool NoRemove { get; set; } = false;
        public bool NoModify { get; set; } = false;
        public bool NoRepair { get; set; } = false;
        public string Comments { get; set; } = string.Empty;
        public string Readme { get; set; } = string.Empty;
        public string ReleaseType { get; set; } = string.Empty;
        public string ParentKeyName { get; set; } = string.Empty;
        public string ParentDisplayName { get; set; } = string.Empty;
        public string InstallType { get; set; } = string.Empty;
        public string SecurityRating { get; set; } = "Unknown";
        public List<string> FileExtensions { get; set; } = new List<string>();
        public List<string> Services { get; set; } = new List<string>();
        public List<string> StartupPrograms { get; set; } = new List<string>();
        public List<string> NetworkConnections { get; set; } = new List<string>();
        public string DigitalSignature { get; set; } = string.Empty;
        public bool IsTrustedPublisher { get; set; } = false;
        public string CertificateInfo { get; set; } = string.Empty;
        public long FileSizeBytes { get; set; } = 0;
        public string FileHash { get; set; } = string.Empty;
        public string InstallationMethod { get; set; } = string.Empty;
        public Dictionary<string, string> AdditionalProperties { get; set; } = new Dictionary<string, string>();
    }
} 