using InstallGuard.Common.Models;

namespace InstallGuard.Service.Services
{
    /// <summary>
    /// Servicio para reportar datos de aplicaciones instaladas a la webapp SaaS
    /// </summary>
    public interface ISoftwareReportingService
    {
        /// <summary>
        /// Envía los datos de una aplicación recién instalada a la webapp
        /// </summary>
        /// <param name="installationEvent">Evento de instalación con todos los datos de la aplicación</param>
        /// <returns>True si se envió exitosamente, false en caso contrario</returns>
        Task<bool> ReportInstallationAsync(InstallationEvent installationEvent);

        /// <summary>
        /// Envía los datos de una aplicación específica a la webapp
        /// </summary>
        /// <param name="applicationInfo">Información de la aplicación</param>
        /// <param name="deviceId">ID del dispositivo</param>
        /// <param name="userId">ID del usuario</param>
        /// <returns>True si se envió exitosamente, false en caso contrario</returns>
        Task<bool> ReportApplicationAsync(ApplicationInfo applicationInfo, string deviceId, string userId);

        /// <summary>
        /// Verifica la conectividad con la webapp
        /// </summary>
        /// <returns>True si hay conectividad, false en caso contrario</returns>
        Task<bool> TestConnectivityAsync();
    }
} 