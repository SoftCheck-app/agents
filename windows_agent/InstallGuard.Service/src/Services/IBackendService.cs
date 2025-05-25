using InstallGuard.Common.Models;

namespace InstallGuard.Service.Services
{
    /// <summary>
    /// Interfaz para la comunicación con el backend
    /// </summary>
    public interface IBackendService
    {
        /// <summary>
        /// Verifica si una instalación está autorizada
        /// </summary>
        /// <param name="request">Solicitud de verificación</param>
        /// <returns>Respuesta de verificación</returns>
        Task<InstallVerificationResponse> VerifyInstallationAsync(InstallVerificationRequest request);
    }
} 