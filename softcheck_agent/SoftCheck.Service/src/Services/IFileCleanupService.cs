namespace SoftCheck.Service.Services
{
    /// <summary>
    /// Interfaz para el servicio de limpieza de archivos
    /// </summary>
    public interface IFileCleanupService
    {
        /// <summary>
        /// Programa la limpieza de un archivo
        /// </summary>
        /// <param name="request">Solicitud de limpieza</param>
        void ScheduleCleanup(CleanupRequest request);
    }

    /// <summary>
    /// Modelo para una solicitud de limpieza
    /// </summary>
    public class CleanupRequest
    {
        /// <summary>
        /// Ruta del archivo a limpiar
        /// </summary>
        public string FilePath { get; set; } = string.Empty;

        /// <summary>
        /// Marca de tiempo de la solicitud
        /// </summary>
        public DateTime Timestamp { get; set; }
    }
} 
