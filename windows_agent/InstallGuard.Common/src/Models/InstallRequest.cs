namespace InstallGuard.Common.Models
{
    /// <summary>
    /// Modelo para la solicitud de instalación enviada desde el controlador al servicio
    /// </summary>
    public class InstallRequest
    {
        /// <summary>
        /// Identificador único de la solicitud de instalación
        /// </summary>
        public long RequestId { get; set; }

        /// <summary>
        /// Ruta completa del archivo que se intenta instalar
        /// </summary>
        public string FilePath { get; set; } = string.Empty;

        /// <summary>
        /// Tamaño del archivo en bytes
        /// </summary>
        public long FileSize { get; set; }

        /// <summary>
        /// Hash del archivo (calculado por el servicio)
        /// </summary>
        public string FileHash { get; set; } = string.Empty;

        /// <summary>
        /// Identificador del proceso que intenta realizar la instalación
        /// </summary>
        public int ProcessId { get; set; }

        /// <summary>
        /// Nombre del proceso que intenta realizar la instalación
        /// </summary>
        public string ProcessName { get; set; } = string.Empty;

        /// <summary>
        /// Nombre del usuario que intenta realizar la instalación
        /// </summary>
        public string Username { get; set; } = string.Empty;

        /// <summary>
        /// Fecha y hora en que se realizó el intento de instalación
        /// </summary>
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    }
} 