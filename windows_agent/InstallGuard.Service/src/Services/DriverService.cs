using InstallGuard.Common.Driver;
using InstallGuard.Common.Models;
using System.Security.Cryptography;
using System.IO;

namespace InstallGuard.Service.Services
{
    /// <summary>
    /// Servicio para la comunicación con el controlador minifiltro
    /// </summary>
    public class DriverService : BackgroundService
    {
        private readonly ILogger<DriverService> _logger;
        private readonly DriverCommunication _driverCommunication;
        private readonly IBackendService _backendService;
        private readonly IFileCleanupService _fileCleanupService;
        private readonly SemaphoreSlim _connectionSemaphore = new SemaphoreSlim(1, 1);
        private readonly TimeSpan _reconnectDelay = TimeSpan.FromSeconds(5);
        private bool _isDriverConnected = false;

        /// <summary>
        /// Constructor
        /// </summary>
        /// <param name="logger">Logger para registrar eventos</param>
        /// <param name="backendService">Servicio para comunicación con el backend</param>
        /// <param name="fileCleanupService">Servicio para limpieza de archivos</param>
        public DriverService(
            ILogger<DriverService> logger,
            IBackendService backendService,
            IFileCleanupService fileCleanupService)
        {
            _logger = logger;
            _driverCommunication = new DriverCommunication(logger);
            _backendService = backendService;
            _fileCleanupService = fileCleanupService;
        }

        /// <summary>
        /// Método principal del servicio en segundo plano
        /// </summary>
        /// <param name="stoppingToken">Token de cancelación</param>
        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            _logger.LogInformation("Servicio de comunicación con el controlador iniciado");

            while (!stoppingToken.IsCancellationRequested)
            {
                // Intentar conectar con el controlador si no está conectado
                if (!_isDriverConnected)
                {
                    await ConnectToDriverAsync();
                }

                // Procesar mensajes del controlador
                if (_isDriverConnected)
                {
                    await ProcessDriverMessagesAsync(stoppingToken);
                }
                else
                {
                    // Si no está conectado, esperar antes de reintentar
                    await Task.Delay(_reconnectDelay, stoppingToken);
                }
            }

            // Desconectar del controlador cuando se detiene el servicio
            _driverCommunication.Disconnect();
            _logger.LogInformation("Servicio de comunicación con el controlador detenido");
        }

        /// <summary>
        /// Conecta con el controlador minifiltro
        /// </summary>
        private async Task ConnectToDriverAsync()
        {
            try
            {
                await _connectionSemaphore.WaitAsync();

                if (!_isDriverConnected)
                {
                    _logger.LogInformation("Intentando conectar con el controlador minifiltro...");
                    _isDriverConnected = _driverCommunication.Connect();

                    if (_isDriverConnected)
                    {
                        _logger.LogInformation("Conexión con el controlador minifiltro establecida correctamente");
                    }
                    else
                    {
                        _logger.LogWarning("No se pudo conectar con el controlador minifiltro. Reintentando en {Delay} segundos", 
                            _reconnectDelay.TotalSeconds);
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error al conectar con el controlador minifiltro");
                _isDriverConnected = false;
            }
            finally
            {
                _connectionSemaphore.Release();
            }
        }

        /// <summary>
        /// Procesa los mensajes recibidos del controlador minifiltro
        /// </summary>
        /// <param name="stoppingToken">Token de cancelación</param>
        private async Task ProcessDriverMessagesAsync(CancellationToken stoppingToken)
        {
            try
            {
                // Leer mensaje del controlador
                var message = _driverCommunication.ReadMessage();
                
                if (message == null)
                {
                    // Si no hay mensaje, esperar un poco antes de volver a intentar
                    await Task.Delay(100, stoppingToken);
                    return;
                }

                // Procesar mensaje según su tipo
                switch (message.Value.CommandCode)
                {
                    case NativeDriverConstants.INSTALLGUARD_CMD_INSTALL_REQUEST:
                        await ProcessInstallRequestAsync(message.Value);
                        break;

                    case NativeDriverConstants.INSTALLGUARD_CMD_CLEANUP_REQUEST:
                        await ProcessCleanupRequestAsync(message.Value);
                        break;

                    default:
                        _logger.LogWarning("Mensaje desconocido recibido del controlador: {CommandCode}", message.Value.CommandCode);
                        break;
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error al procesar mensajes del controlador minifiltro");
                
                // Si hay un error de comunicación, marcar como desconectado
                if (ex is System.IO.IOException || ex is System.UnauthorizedAccessException)
                {
                    _isDriverConnected = false;
                    _driverCommunication.Disconnect();
                }
            }
        }

        /// <summary>
        /// Procesa una solicitud de instalación recibida del controlador
        /// </summary>
        /// <param name="message">Mensaje recibido</param>
        private async Task ProcessInstallRequestAsync(InstallGuardMessage message)
        {
            _logger.LogInformation("Procesando solicitud de instalación: {FilePath}", message.FilePath);

            try
            {
                // Convertir mensaje a modelo de solicitud
                var installRequest = new InstallRequest
                {
                    RequestId = (long)message.CommandCode,
                    FilePath = message.FilePath,
                    FileSize = message.FileSize,
                    ProcessId = (int)message.ProcessId,
                    ProcessName = message.ProcessName,
                    Username = message.Username,
                    Timestamp = DateTime.Now
                };

                // Calcular hash del archivo si existe
                if (File.Exists(message.FilePath))
                {
                    installRequest.FileHash = await CalculateFileHashAsync(message.FilePath);
                }
                else
                {
                    _logger.LogWarning("Archivo no encontrado para calcular hash: {FilePath}", message.FilePath);
                }

                // Enviar solicitud al backend para verificación
                var verificationRequest = MapToVerificationRequest(installRequest);
                var verificationResponse = await _backendService.VerifyInstallationAsync(verificationRequest);

                // Enviar respuesta al controlador
                var response = InstallGuardResponse.Create(
                    (uint)installRequest.RequestId,
                    verificationResponse.IsApproved,
                    verificationResponse.Reason);

                bool sent = _driverCommunication.SendResponse(response);

                if (sent)
                {
                    _logger.LogInformation("Respuesta enviada al controlador: {Allow}, {Reason}",
                        response.AllowInstallation, response.Reason);
                }
                else
                {
                    _logger.LogError("Error al enviar respuesta al controlador");
                }

                // Si se deniega la instalación, programar limpieza de archivos
                if (!verificationResponse.IsApproved)
                {
                    _fileCleanupService.ScheduleCleanup(new CleanupRequest
                    {
                        FilePath = message.FilePath,
                        Timestamp = DateTime.Now
                    });
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error al procesar solicitud de instalación");

                // En caso de error, denegar por defecto por seguridad
                try
                {
                    var response = InstallGuardResponse.Create(
                        (uint)message.CommandCode,
                        false,
                        "Error al procesar la solicitud: " + ex.Message);

                    _driverCommunication.SendResponse(response);
                }
                catch (Exception sendEx)
                {
                    _logger.LogError(sendEx, "Error al enviar respuesta de denegación al controlador");
                }
            }
        }

        /// <summary>
        /// Procesa una solicitud de limpieza recibida del controlador
        /// </summary>
        /// <param name="message">Mensaje recibido</param>
        private async Task ProcessCleanupRequestAsync(InstallGuardMessage message)
        {
            _logger.LogInformation("Procesando solicitud de limpieza: {FilePath}", message.FilePath);

            try
            {
                // Programar limpieza de archivos
                _fileCleanupService.ScheduleCleanup(new CleanupRequest
                {
                    FilePath = message.FilePath,
                    Timestamp = DateTime.Now
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error al procesar solicitud de limpieza");
            }
        }

        /// <summary>
        /// Calcula el hash SHA-256 de un archivo
        /// </summary>
        /// <param name="filePath">Ruta del archivo</param>
        /// <returns>Hash del archivo en formato hexadecimal</returns>
        private async Task<string> CalculateFileHashAsync(string filePath)
        {
            try
            {
                using (var sha256 = SHA256.Create())
                using (var stream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                {
                    byte[] hash = await sha256.ComputeHashAsync(stream);
                    return BitConverter.ToString(hash).Replace("-", "").ToLowerInvariant();
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error al calcular hash del archivo: {FilePath}", filePath);
                return string.Empty;
            }
        }

        /// <summary>
        /// Mapea una solicitud de instalación a una solicitud de verificación para el backend
        /// </summary>
        /// <param name="request">Solicitud de instalación</param>
        /// <returns>Solicitud de verificación</returns>
        private InstallVerificationRequest MapToVerificationRequest(InstallRequest request)
        {
            return new InstallVerificationRequest
            {
                FilePath = request.FilePath,
                FileName = Path.GetFileName(request.FilePath),
                FileHash = request.FileHash,
                FileSize = request.FileSize,
                ProcessName = request.ProcessName,
                Username = request.Username,
                MachineName = Environment.MachineName,
                Timestamp = request.Timestamp
            };
        }

        /// <summary>
        /// Libera los recursos utilizados
        /// </summary>
        public override void Dispose()
        {
            _driverCommunication?.Dispose();
            _connectionSemaphore?.Dispose();
            base.Dispose();
        }
    }
} 