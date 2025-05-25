namespace InstallGuard.Common.Models
{
    /// <summary>
    /// Modelo para la solicitud de limpieza de archivos de instalación
    /// </summary>
    public class CleanupRequest
    {
        /// <summary>
        /// Ruta completa del archivo principal a limpiar
        /// </summary>
        public string FilePath { get; set; } = string.Empty;

        /// <summary>
        /// Fecha y hora en que se solicitó la limpieza
        /// </summary>
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    }
} 