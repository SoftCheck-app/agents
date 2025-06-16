using SoftCheck.Common.Models;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Win32;
using System.Management;
using System.Security.Cryptography;
using System.Text;
using System.Diagnostics;
using System.IO;

namespace SoftCheck.Service.Services
{
    public class InstallationMonitorService : BackgroundService, IInstallationMonitorService
    {
        private readonly ILogger<InstallationMonitorService> _logger;
        private readonly INotificationService _notificationService;
        private readonly ISoftwareReportingService _softwareReportingService;
        private ManagementEventWatcher? _wmiWatcher;
        private Timer? _registryTimer;
        private Dictionary<string, ApplicationInfo> _lastKnownApps = new();
        private readonly object _lockObject = new object();
        private bool _isMonitoring = false;

        public event EventHandler<InstallationEvent>? InstallationDetected;
        public bool IsMonitoring => _isMonitoring;

        // Rutas del registro donde se almacenan las aplicaciones instaladas
        private readonly string[] _registryPaths = new[]
        {
            @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
            @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
        };

        public InstallationMonitorService(
            ILogger<InstallationMonitorService> logger,
            INotificationService notificationService,
            ISoftwareReportingService softwareReportingService)
        {
            _logger = logger;
            _notificationService = notificationService;
            _softwareReportingService = softwareReportingService;
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            _logger.LogInformation("InstallationMonitorService iniciando...");
            
            try
            {
                await StartMonitoringAsync(stoppingToken);
                
                // Mantener el servicio ejecutándose
                while (!stoppingToken.IsCancellationRequested)
                {
                    await Task.Delay(5000, stoppingToken);
                }
            }
            catch (OperationCanceledException)
            {
                _logger.LogInformation("InstallationMonitorService detenido por cancelación");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error en InstallationMonitorService");
            }
            finally
            {
                await StopMonitoringAsync();
            }
        }

        public async Task StartMonitoringAsync(CancellationToken cancellationToken)
        {
            if (_isMonitoring)
                return;

            _logger.LogInformation("Iniciando monitoreo de instalaciones...");

            try
            {
                // Cargar estado inicial de aplicaciones instaladas
                await LoadInitialApplicationsAsync();

                // Enviar inventario completo inicial a la webapp
                _logger.LogInformation("Enviando inventario inicial completo a webapp...");
                await SendAllApplicationsToWebappAsync();

                // Iniciar monitoreo WMI para eventos de instalación
                StartWMIMonitoring();

                // Iniciar monitoreo periódico del registro
                StartRegistryMonitoring();

                _isMonitoring = true;
                _logger.LogInformation("Monitoreo de instalaciones iniciado exitosamente");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error al iniciar monitoreo de instalaciones");
                throw;
            }
        }

        public async Task StopMonitoringAsync()
        {
            if (!_isMonitoring)
                return;

            _logger.LogInformation("Deteniendo monitoreo de instalaciones...");

            try
            {
                _wmiWatcher?.Stop();
                _wmiWatcher?.Dispose();
                _wmiWatcher = null;

                _registryTimer?.Dispose();
                _registryTimer = null;

                _isMonitoring = false;
                _logger.LogInformation("Monitoreo de instalaciones detenido");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error al detener monitoreo de instalaciones");
            }
        }

        private async Task LoadInitialApplicationsAsync()
        {
            _logger.LogInformation("Cargando estado inicial de aplicaciones instaladas...");
            
            var apps = await GetInstalledApplicationsAsync();
            
            lock (_lockObject)
            {
                _lastKnownApps.Clear();
                foreach (var app in apps)
                {
                    if (!string.IsNullOrEmpty(app.RegistryKey))
                    {
                        _lastKnownApps[app.RegistryKey] = app;
                    }
                }
            }

            _logger.LogInformation($"Cargadas {_lastKnownApps.Count} aplicaciones instaladas");
        }

        private void StartWMIMonitoring()
        {
            try
            {
                // Monitorear eventos de instalación/desinstalación usando WMI
                var query = new WqlEventQuery(
                    "SELECT * FROM Win32_VolumeChangeEvent WHERE EventType = 2");

                _wmiWatcher = new ManagementEventWatcher(query);
                _wmiWatcher.EventArrived += OnWMIEventArrived;
                _wmiWatcher.Start();

                _logger.LogInformation("Monitoreo WMI iniciado");
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "No se pudo iniciar monitoreo WMI, usando solo monitoreo de registro");
            }
        }

        private void StartRegistryMonitoring()
        {
            // Verificar cambios en el registro cada 30 segundos
            _registryTimer = new Timer(CheckRegistryChanges, null, TimeSpan.Zero, TimeSpan.FromSeconds(30));
            _logger.LogInformation("Monitoreo de registro iniciado");
        }

        private async void OnWMIEventArrived(object sender, EventArrivedEventArgs e)
        {
            try
            {
                _logger.LogDebug("Evento WMI detectado, verificando cambios en aplicaciones...");
                
                // Esperar un poco para que se complete la instalación
                await Task.Delay(2000);
                
                // Verificar cambios en el registro
                await CheckForApplicationChangesAsync();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error procesando evento WMI");
            }
        }

        private async void CheckRegistryChanges(object? state)
        {
            try
            {
                await CheckForApplicationChangesAsync();
                
                // Enviar inventario completo de aplicaciones cada vez
                await SendAllApplicationsToWebappAsync();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error verificando cambios en registro");
            }
        }

        private async Task CheckForApplicationChangesAsync()
        {
            try
            {
                var currentApps = await GetInstalledApplicationsAsync();
                var currentAppsDict = currentApps.ToDictionary(app => app.RegistryKey, app => app);

                List<InstallationEvent> events = new();

                lock (_lockObject)
                {
                    // Detectar nuevas instalaciones
                    foreach (var kvp in currentAppsDict)
                    {
                        if (!_lastKnownApps.ContainsKey(kvp.Key))
                        {
                            var installEvent = new InstallationEvent
                            {
                                EventType = "Install",
                                Application = kvp.Value,
                                DetectionMethod = "Registry",
                                UserContext = Environment.UserName,
                                SessionId = Environment.ProcessId.ToString()
                            };

                            // Analizar riesgo de seguridad
                            AnalyzeSecurityRisk(installEvent);

                            events.Add(installEvent);
                            _logger.LogInformation($"Nueva instalación detectada: {kvp.Value.Name} v{kvp.Value.Version}");
                        }
                    }

                    // Detectar desinstalaciones
                    foreach (var kvp in _lastKnownApps)
                    {
                        if (!currentAppsDict.ContainsKey(kvp.Key))
                        {
                            var uninstallEvent = new InstallationEvent
                            {
                                EventType = "Uninstall",
                                Application = kvp.Value,
                                DetectionMethod = "Registry",
                                UserContext = Environment.UserName,
                                SessionId = Environment.ProcessId.ToString(),
                                RequiresUserNotification = false // No notificar desinstalaciones por defecto
                            };

                            events.Add(uninstallEvent);
                            _logger.LogInformation($"Desinstalación detectada: {kvp.Value.Name}");
                        }
                    }

                    // Actualizar estado conocido
                    _lastKnownApps = currentAppsDict;
                }

                // Procesar eventos detectados
                foreach (var installEvent in events)
                {
                    if (installEvent.RequiresUserNotification)
                    {
                        // Mostrar notificación al usuario
                        await _notificationService.ShowInstallationNotificationAsync(installEvent);
                        installEvent.NotificationShown = true;
                        installEvent.NotificationShownAt = DateTime.Now;
                    }

                    // Reportar instalación a la webapp SaaS (solo para instalaciones)
                    if (installEvent.EventType == "Install")
                    {
                        try
                        {
                            _logger.LogInformation($"Reportando instalación a webapp: {installEvent.Application.Name}");
                            var reportSuccess = await _softwareReportingService.ReportInstallationAsync(installEvent);
                            
                            if (reportSuccess)
                            {
                                _logger.LogInformation($"Instalación reportada exitosamente: {installEvent.Application.Name}");
                            }
                            else
                            {
                                _logger.LogWarning($"No se pudo reportar instalación: {installEvent.Application.Name}");
                            }
                        }
                        catch (Exception ex)
                        {
                            _logger.LogError(ex, $"Error reportando instalación a webapp: {installEvent.Application.Name}");
                        }
                    }

                    // Disparar evento
                    InstallationDetected?.Invoke(this, installEvent);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error verificando cambios en aplicaciones");
            }
        }

        /// <summary>
        /// Envía todas las aplicaciones instaladas a la webapp SaaS
        /// </summary>
        private async Task SendAllApplicationsToWebappAsync()
        {
            try
            {
                _logger.LogInformation("Enviando inventario completo de aplicaciones a webapp...");
                
                var allApplications = await GetInstalledApplicationsAsync();
                _logger.LogInformation($"Encontradas {allApplications.Count} aplicaciones instaladas para enviar");

                if (allApplications.Count == 0)
                {
                    _logger.LogInformation("No hay aplicaciones para enviar");
                    return;
                }

                // Enriquecer información de todas las aplicaciones antes del envío
                foreach (var app in allApplications)
                {
                    try
                    {
                        EnrichApplicationInfo(app);
                    }
                    catch (Exception ex)
                    {
                        _logger.LogWarning(ex, $"Error enriqueciendo información de {app.Name}");
                    }
                }

                // Usar el método de envío en lotes para mejor rendimiento
                var (successCount, errorCount) = await _softwareReportingService.ReportInventoryBatchAsync(allApplications, batchSize: 5);

                _logger.LogInformation($"Inventario completo enviado: {successCount} exitosas, {errorCount} errores de {allApplications.Count} total");

                // Log adicional si hay muchos errores
                if (errorCount > 0)
                {
                    var errorPercentage = (double)errorCount / allApplications.Count * 100;
                    if (errorPercentage > 20)
                    {
                        _logger.LogWarning($"Alto porcentaje de errores en envío de inventario: {errorPercentage:F1}%");
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error enviando inventario completo a webapp");
            }
        }

        public async Task<List<ApplicationInfo>> GetInstalledApplicationsAsync()
        {
            var applications = new List<ApplicationInfo>();

            await Task.Run(() =>
            {
                foreach (var registryPath in _registryPaths)
                {
                    try
                    {
                        using var key = Registry.LocalMachine.OpenSubKey(registryPath);
                        if (key == null) continue;

                        foreach (var subKeyName in key.GetSubKeyNames())
                        {
                            try
                            {
                                using var subKey = key.OpenSubKey(subKeyName);
                                if (subKey == null) continue;

                                var app = ExtractApplicationInfo(subKey, $"{registryPath}\\{subKeyName}");
                                if (app != null && !string.IsNullOrEmpty(app.Name))
                                {
                                    applications.Add(app);
                                }
                            }
                            catch (Exception ex)
                            {
                                _logger.LogDebug(ex, $"Error leyendo subkey {subKeyName}");
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        _logger.LogWarning(ex, $"Error accediendo a registro {registryPath}");
                    }
                }
            });

            return applications;
        }

        public async Task<ApplicationInfo?> GetApplicationInfoAsync(string registryKey)
        {
            return await Task.Run(() =>
            {
                try
                {
                    using var key = Registry.LocalMachine.OpenSubKey(registryKey);
                    if (key == null) return null;

                    return ExtractApplicationInfo(key, registryKey);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, $"Error obteniendo información de aplicación: {registryKey}");
                    return null;
                }
            });
        }

        private ApplicationInfo? ExtractApplicationInfo(RegistryKey key, string registryPath)
        {
            try
            {
                var displayName = key.GetValue("DisplayName")?.ToString();
                if (string.IsNullOrEmpty(displayName))
                    return null;

                // Filtrar componentes del sistema y actualizaciones
                if (IsSystemComponent(key, displayName))
                    return null;

                var app = new ApplicationInfo
                {
                    Name = displayName,
                    Version = key.GetValue("DisplayVersion")?.ToString() ?? "",
                    Publisher = key.GetValue("Publisher")?.ToString() ?? "",
                    InstallLocation = key.GetValue("InstallLocation")?.ToString() ?? "",
                    InstallDate = key.GetValue("InstallDate")?.ToString() ?? "",
                    UninstallString = key.GetValue("UninstallString")?.ToString() ?? "",
                    DisplayIcon = key.GetValue("DisplayIcon")?.ToString() ?? "",
                    EstimatedSize = FormatSize(key.GetValue("EstimatedSize")),
                    RegistryKey = registryPath,
                    Description = key.GetValue("Comments")?.ToString() ?? "",
                    HelpLink = key.GetValue("HelpLink")?.ToString() ?? "",
                    URLInfoAbout = key.GetValue("URLInfoAbout")?.ToString() ?? "",
                    Contact = key.GetValue("Contact")?.ToString() ?? "",
                    ModifyPath = key.GetValue("ModifyPath")?.ToString() ?? "",
                    InstallSource = key.GetValue("InstallSource")?.ToString() ?? "",
                    Language = key.GetValue("Language")?.ToString() ?? "",
                    NoRemove = key.GetValue("NoRemove")?.ToString() == "1",
                    NoModify = key.GetValue("NoModify")?.ToString() == "1",
                    NoRepair = key.GetValue("NoRepair")?.ToString() == "1",
                    ReleaseType = key.GetValue("ReleaseType")?.ToString() ?? "",
                    ParentKeyName = key.GetValue("ParentKeyName")?.ToString() ?? "",
                    ParentDisplayName = key.GetValue("ParentDisplayName")?.ToString() ?? ""
                };

                // Obtener información adicional
                EnrichApplicationInfo(app);

                return app;
            }
            catch (Exception ex)
            {
                _logger.LogDebug(ex, $"Error extrayendo información de aplicación: {registryPath}");
                return null;
            }
        }

        private bool IsSystemComponent(RegistryKey key, string displayName)
        {
            // Filtrar componentes del sistema
            var systemComponent = key.GetValue("SystemComponent")?.ToString();
            if (systemComponent == "1")
                return true;

            // Filtrar actualizaciones de Windows
            if (displayName.Contains("Update for") || 
                displayName.Contains("Hotfix for") ||
                displayName.Contains("Security Update") ||
                displayName.StartsWith("KB") ||
                displayName.Contains("Microsoft Visual C++") && displayName.Contains("Redistributable"))
                return true;

            // Filtrar por publisher
            var publisher = key.GetValue("Publisher")?.ToString() ?? "";
            if (publisher.Contains("Microsoft Corporation") && 
                (displayName.Contains("Microsoft .NET") || displayName.Contains("Microsoft Visual")))
                return true;

            return false;
        }

        private void EnrichApplicationInfo(ApplicationInfo app)
        {
            try
            {
                // Obtener información del archivo ejecutable
                if (!string.IsNullOrEmpty(app.InstallLocation) && Directory.Exists(app.InstallLocation))
                {
                    var exeFiles = Directory.GetFiles(app.InstallLocation, "*.exe", SearchOption.TopDirectoryOnly);
                    if (exeFiles.Length > 0)
                    {
                        var mainExe = exeFiles[0];
                        var fileInfo = new FileInfo(mainExe);
                        app.FileSizeBytes = fileInfo.Length;

                        // Obtener información de versión
                        var versionInfo = FileVersionInfo.GetVersionInfo(mainExe);
                        if (string.IsNullOrEmpty(app.Description))
                            app.Description = versionInfo.FileDescription ?? "";

                        // Verificar firma digital
                        app.DigitalSignature = GetDigitalSignatureInfo(mainExe);
                    }
                }

                // Determinar arquitectura
                app.Architecture = Environment.Is64BitOperatingSystem ? "x64" : "x86";

                // Obtener hash del archivo principal
                if (!string.IsNullOrEmpty(app.InstallLocation))
                {
                    app.FileHash = CalculateFileHash(app.InstallLocation);
                }
            }
            catch (Exception ex)
            {
                _logger.LogDebug(ex, $"Error enriqueciendo información de {app.Name}");
            }
        }

        private void AnalyzeSecurityRisk(InstallationEvent installEvent)
        {
            var app = installEvent.Application;
            var riskFactors = new List<string>();
            var riskScore = 0;

            // Verificar firma digital
            if (string.IsNullOrEmpty(app.DigitalSignature))
            {
                riskFactors.Add("Sin firma digital");
                riskScore += 30;
            }

            // Verificar publisher conocido
            if (string.IsNullOrEmpty(app.Publisher))
            {
                riskFactors.Add("Publisher desconocido");
                riskScore += 20;
            }

            // Verificar ubicación de instalación sospechosa
            if (!string.IsNullOrEmpty(app.InstallLocation))
            {
                var suspiciousPaths = new[] { @"C:\Users", @"C:\Temp", @"C:\Windows\Temp" };
                if (suspiciousPaths.Any(path => app.InstallLocation.StartsWith(path, StringComparison.OrdinalIgnoreCase)))
                {
                    riskFactors.Add("Ubicación de instalación sospechosa");
                    riskScore += 25;
                }
            }

            // Verificar nombre sospechoso
            var suspiciousNames = new[] { "crack", "keygen", "patch", "hack", "cheat" };
            if (suspiciousNames.Any(name => app.Name.Contains(name, StringComparison.OrdinalIgnoreCase)))
            {
                riskFactors.Add("Nombre sospechoso");
                riskScore += 40;
            }

            // Determinar nivel de riesgo
            installEvent.RiskLevel = riskScore switch
            {
                >= 70 => "Critical",
                >= 50 => "High",
                >= 30 => "Medium",
                _ => "Low"
            };

            installEvent.SecurityFlags = riskFactors;

            // Generar recomendación
            installEvent.RecommendedAction = installEvent.RiskLevel switch
            {
                "Critical" => "Se recomienda desinstalar inmediatamente y ejecutar un análisis antivirus",
                "High" => "Verificar la legitimidad de la aplicación antes de usar",
                "Medium" => "Monitorear el comportamiento de la aplicación",
                _ => "Aplicación parece segura"
            };
        }

        private string FormatSize(object? sizeValue)
        {
            if (sizeValue == null) return "";
            
            if (int.TryParse(sizeValue.ToString(), out int sizeKB))
            {
                if (sizeKB < 1024)
                    return $"{sizeKB} KB";
                else if (sizeKB < 1024 * 1024)
                    return $"{sizeKB / 1024:F1} MB";
                else
                    return $"{sizeKB / (1024 * 1024):F1} GB";
            }
            
            return sizeValue.ToString() ?? "";
        }

        private string GetDigitalSignatureInfo(string filePath)
        {
            try
            {
                // Aquí se podría implementar verificación de firma digital
                // Por simplicidad, retornamos información básica
                return File.Exists(filePath) ? "Present" : "Not Found";
            }
            catch
            {
                return "Unknown";
            }
        }

        private string CalculateFileHash(string installLocation)
        {
            try
            {
                if (!Directory.Exists(installLocation))
                    return "";

                var exeFiles = Directory.GetFiles(installLocation, "*.exe", SearchOption.TopDirectoryOnly);
                if (exeFiles.Length == 0)
                    return "";

                using var sha256 = SHA256.Create();
                using var stream = File.OpenRead(exeFiles[0]);
                var hash = sha256.ComputeHash(stream);
                return Convert.ToHexString(hash);
            }
            catch
            {
                return "";
            }
        }

        public override void Dispose()
        {
            StopMonitoringAsync().Wait();
            base.Dispose();
        }
    }
} 
