using InstallGuard.Service.Services;
using Microsoft.Extensions.Hosting.WindowsServices;

var builder = Host.CreateDefaultBuilder(args)
    .UseWindowsService(options =>
    {
        options.ServiceName = "InstallGuard Service";
    })
    .ConfigureLogging(logging =>
    {
        // Configurar logging para servicio de Windows
        logging.ClearProviders();
        logging.AddConsole();
        logging.AddEventLog(eventLogSettings =>
        {
            eventLogSettings.SourceName = "InstallGuard Service";
        });
    })
    .ConfigureServices((context, services) =>
    {
        // Registrar servicios básicos
        services.AddHttpClient();
        services.AddSingleton<IBackendService, BackendService>();
        services.AddSingleton<IFileCleanupService, FileCleanupService>();
        services.AddSingleton<INotificationService, NotificationService>();
        services.AddSingleton<ISoftwareReportingService, SoftwareReportingService>();
        services.AddSingleton<IInstallationMonitorService, InstallationMonitorService>();
        services.AddHostedService<FileCleanupService>(sp => (FileCleanupService)sp.GetRequiredService<IFileCleanupService>());
        
        // Solo registrar DriverService si está habilitado en configuración
        var enableDriver = context.Configuration.GetValue<bool>("Features:EnableDriver", false);
        if (enableDriver)
        {
            services.AddHostedService<DriverService>();
        }
        
        // Siempre registrar AgentPingService (necesario para comunicación con backend)
        services.AddHostedService<AgentPingService>();
        
        // Solo registrar InstallationMonitorService si no está en modo pasivo
        var passiveMode = context.Configuration.GetValue<bool>("Features:PassiveMode", false);
        var enableInstallationMonitoring = context.Configuration.GetValue<bool>("Features:EnableInstallationMonitoring", true);
        
        if (!passiveMode && enableInstallationMonitoring)
        {
            services.AddHostedService<InstallationMonitorService>(sp => (InstallationMonitorService)sp.GetRequiredService<IInstallationMonitorService>());
        }
        
        // DESACTIVADO: Servicio de prueba (solo para desarrollo)
        // services.AddHostedService<InstallationTestService>();
    });

var host = builder.Build();

// Log de inicio del servicio
var logger = host.Services.GetRequiredService<ILogger<Program>>();
var configuration = host.Services.GetRequiredService<IConfiguration>();
var passiveMode = configuration.GetValue<bool>("Features:PassiveMode", false);

if (passiveMode)
{
    logger.LogInformation("InstallGuard Service iniciando en MODO PASIVO...");
    logger.LogInformation("- Monitoreo de instalaciones: DESACTIVADO");
    logger.LogInformation("- Ping al backend: ACTIVADO");
    logger.LogInformation("- Inventario bajo demanda: DISPONIBLE");
}
else
{
    logger.LogInformation("InstallGuard Service iniciando en MODO ACTIVO...");
}

try
{
    await host.RunAsync();
}
catch (Exception ex)
{
    logger.LogCritical(ex, "Error crítico en InstallGuard Service");
    throw;
} 