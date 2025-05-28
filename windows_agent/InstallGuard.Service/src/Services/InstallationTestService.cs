using InstallGuard.Common.Models;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace InstallGuard.Service.Services
{
    public class InstallationTestService : BackgroundService
    {
        private readonly ILogger<InstallationTestService> _logger;
        private readonly INotificationService _notificationService;
        private readonly IInstallationMonitorService _installationMonitorService;

        public InstallationTestService(
            ILogger<InstallationTestService> logger,
            INotificationService notificationService,
            IInstallationMonitorService installationMonitorService)
        {
            _logger = logger;
            _notificationService = notificationService;
            _installationMonitorService = installationMonitorService;
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            // Esperar 30 segundos antes de ejecutar la prueba
            await Task.Delay(30000, stoppingToken);

            if (stoppingToken.IsCancellationRequested)
                return;

            _logger.LogInformation("Ejecutando prueba de detección de instalaciones...");

            try
            {
                // Crear evento de prueba
                var testEvent = CreateTestInstallationEvent();
                
                // Mostrar notificación de prueba
                await _notificationService.ShowInstallationNotificationAsync(testEvent);
                
                _logger.LogInformation("Prueba de notificación completada");

                // Mostrar aplicaciones instaladas actualmente
                await LogInstalledApplicationsAsync();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error en prueba de instalaciones");
            }
        }

        private InstallationEvent CreateTestInstallationEvent()
        {
            var testApp = new ApplicationInfo
            {
                Name = "Aplicación de Prueba InstallGuard",
                Version = "1.0.0",
                Publisher = "InstallGuard Security",
                InstallLocation = @"C:\Program Files\TestApp",
                InstallDate = DateTime.Now.ToString("yyyyMMdd"),
                EstimatedSize = "15.2 MB",
                Architecture = "x64",
                Description = "Esta es una aplicación de prueba para demostrar el sistema de detección de instalaciones de InstallGuard.",
                DigitalSignature = "Present",
                RegistryKey = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\TestApp"
            };

            var testEvent = new InstallationEvent
            {
                EventType = "Install",
                Application = testApp,
                DetectionMethod = "Test",
                UserContext = Environment.UserName,
                SessionId = Environment.ProcessId.ToString(),
                RiskLevel = "Low",
                RecommendedAction = "Esta es una aplicación de prueba segura para demostrar el sistema de notificaciones.",
                SecurityFlags = new List<string> { "Aplicación de prueba", "Entorno de desarrollo" }
            };

            return testEvent;
        }

        private async Task LogInstalledApplicationsAsync()
        {
            try
            {
                _logger.LogInformation("Obteniendo lista de aplicaciones instaladas...");
                
                var apps = await _installationMonitorService.GetInstalledApplicationsAsync();
                
                _logger.LogInformation($"Total de aplicaciones instaladas: {apps.Count}");
                
                // Mostrar las primeras 10 aplicaciones como ejemplo
                var topApps = apps.Take(10).ToList();
                
                foreach (var app in topApps)
                {
                    _logger.LogInformation($"App: {app.Name} v{app.Version} - Publisher: {app.Publisher}");
                }
                
                if (apps.Count > 10)
                {
                    _logger.LogInformation($"... y {apps.Count - 10} aplicaciones más");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error obteniendo aplicaciones instaladas");
            }
        }
    }
} 