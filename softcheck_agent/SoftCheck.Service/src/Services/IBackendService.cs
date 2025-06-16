using SoftCheck.Common.Models;

namespace SoftCheck.Service.Services
{
    /// <summary>
    /// Interfaz para el servicio de comunicación con el backend
    /// </summary>
    public interface IBackendService
    {
        /// <summary>
        /// Verifica una solicitud de instalación con el backend
        /// </summary>
        /// <param name="request">Solicitud de verificación</param>
        /// <returns>Respuesta de verificación</returns>
        Task<InstallVerificationResponse> VerifyInstallationAsync(InstallVerificationRequest request);
    }

    /// <summary>
    /// Modelo para una solicitud de verificación de instalación
    /// </summary>
    public class InstallVerificationRequest
    {
        public string FilePath { get; set; } = string.Empty;
        public long FileSize { get; set; }
        public string? FileHash { get; set; }
        public int ProcessId { get; set; }
        public string ProcessName { get; set; } = string.Empty;
        public string Username { get; set; } = string.Empty;
        public DateTime Timestamp { get; set; }
        public string MachineName { get; set; } = Environment.MachineName;
    }

    /// <summary>
    /// Modelo para una respuesta de verificación de instalación
    /// </summary>
    public class InstallVerificationResponse
    {
        public bool IsApproved { get; set; }
        public string Reason { get; set; } = string.Empty;
    }
} 
