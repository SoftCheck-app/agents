using SoftCheck.Common.Models;

namespace SoftCheck.Service.Services
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

        /// <summary>
        /// Envía múltiples aplicaciones en lotes para optimizar el rendimiento del inventario completo
        /// </summary>
        /// <param name="applications">Lista de aplicaciones a enviar</param>
        /// <param name="batchSize">Tamaño del lote (por defecto 10)</param>
        /// <returns>Tupla con el número de aplicaciones enviadas exitosamente y fallidas</returns>
        Task<(int successful, int failed)> ReportInventoryBatchAsync(List<ApplicationInfo> applications, int batchSize = 10);
    }
} 
