namespace InstallGuard.Common.Models
{
    /// <summary>
    /// Modelo para la solicitud de verificación enviada al backend
    /// </summary>
    public class InstallVerificationRequest
    {
        /// <summary>
        /// Ruta completa del archivo que se intenta instalar
        /// </summary>
        public string FilePath { get; set; } = string.Empty;

        /// <summary>
        /// Nombre del archivo sin la ruta
        /// </summary>
        public string FileName { get; set; } = string.Empty;

        /// <summary>
        /// Hash SHA-256 del archivo
        /// </summary>
        public string FileHash { get; set; } = string.Empty;

        /// <summary>
        /// Tamaño del archivo en bytes
        /// </summary>
        public long FileSize { get; set; }

        /// <summary>
        /// Nombre del proceso que intenta realizar la instalación
        /// </summary>
        public string ProcessName { get; set; } = string.Empty;

        /// <summary>
        /// Nombre del usuario que intenta realizar la instalación
        /// </summary>
        public string Username { get; set; } = string.Empty;

        /// <summary>
        /// Nombre del equipo donde se está realizando la instalación
        /// </summary>
        public string MachineName { get; set; } = string.Empty;

        /// <summary>
        /// Fecha y hora en que se realizó el intento de instalación
        /// </summary>
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    }

    /// <summary>
    /// Modelo para la respuesta de verificación recibida del backend
    /// </summary>
    public class InstallVerificationResponse
    {
        /// <summary>
        /// Indica si se permite la instalación
        /// </summary>
        public bool IsApproved { get; set; }

        /// <summary>
        /// Razón por la que se permite o se deniega la instalación
        /// </summary>
        public string Reason { get; set; } = string.Empty;

        /// <summary>
        /// Nivel de confianza en la decisión (0-100)
        /// </summary>
        public int ConfidenceLevel { get; set; }

        /// <summary>
        /// Identificador único de la verificación en el backend
        /// </summary>
        public string VerificationId { get; set; } = string.Empty;

        /// <summary>
        /// Fecha y hora en que se generó la respuesta
        /// </summary>
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    }
} 