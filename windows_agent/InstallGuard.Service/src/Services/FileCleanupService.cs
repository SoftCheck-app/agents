using System.Collections.Concurrent;

namespace InstallGuard.Service.Services
{
    /// <summary>
    /// Implementación del servicio de limpieza de archivos
    /// </summary>
    public class FileCleanupService : BackgroundService, IFileCleanupService
    {
        private readonly ILogger<FileCleanupService> _logger;
        private readonly ConcurrentQueue<CleanupRequest> _cleanupQueue;
        private readonly TimeSpan _cleanupDelay = TimeSpan.FromMinutes(5);

        /// <summary>
        /// Constructor
        /// </summary>
        /// <param name="logger">Logger para registrar eventos</param>
        public FileCleanupService(ILogger<FileCleanupService> logger)
        {
            _logger = logger;
            _cleanupQueue = new ConcurrentQueue<CleanupRequest>();
        }

        /// <summary>
        /// Programa la limpieza de un archivo
        /// </summary>
        /// <param name="request">Solicitud de limpieza</param>
        public void ScheduleCleanup(CleanupRequest request)
        {
            _cleanupQueue.Enqueue(request);
            _logger.LogInformation("Limpieza programada para el archivo: {FilePath}", request.FilePath);
        }

        /// <summary>
        /// Método principal del servicio en segundo plano
        /// </summary>
        /// <param name="stoppingToken">Token de cancelación</param>
        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            _logger.LogInformation("Servicio de limpieza de archivos iniciado");

            while (!stoppingToken.IsCancellationRequested)
            {
                try
                {
                    // Procesar solicitudes de limpieza
                    while (_cleanupQueue.TryDequeue(out var request))
                    {
                        // Esperar el tiempo de retraso antes de intentar eliminar el archivo
                        var elapsedTime = DateTime.Now - request.Timestamp;
                        if (elapsedTime < _cleanupDelay)
                        {
                            var remainingDelay = _cleanupDelay - elapsedTime;
                            await Task.Delay(remainingDelay, stoppingToken);
                        }

                        // Intentar eliminar el archivo
                        try
                        {
                            if (File.Exists(request.FilePath))
                            {
                                File.Delete(request.FilePath);
                                _logger.LogInformation("Archivo eliminado correctamente: {FilePath}", request.FilePath);
                            }
                            else
                            {
                                _logger.LogWarning("Archivo no encontrado para eliminar: {FilePath}", request.FilePath);
                            }
                        }
                        catch (Exception ex)
                        {
                            _logger.LogError(ex, "Error al eliminar archivo: {FilePath}", request.FilePath);
                            
                            // Reintentar más tarde si el archivo está en uso
                            if (ex is IOException)
                            {
                                request.Timestamp = DateTime.Now;
                                _cleanupQueue.Enqueue(request);
                            }
                        }
                    }

                    // Esperar antes de verificar nuevas solicitudes
                    await Task.Delay(1000, stoppingToken);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Error en el servicio de limpieza de archivos");
                    await Task.Delay(5000, stoppingToken);
                }
            }

            _logger.LogInformation("Servicio de limpieza de archivos detenido");
        }
    }
} 