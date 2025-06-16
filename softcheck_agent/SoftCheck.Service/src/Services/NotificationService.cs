using SoftCheck.Common.Models;
using Microsoft.Extensions.Logging;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace SoftCheck.Service.Services
{
    public class NotificationService : INotificationService
    {
        private readonly ILogger<NotificationService> _logger;

        public bool IsNotificationServiceAvailable => true;

        public NotificationService(ILogger<NotificationService> logger)
        {
            _logger = logger;
        }

        public async Task ShowInstallationNotificationAsync(InstallationEvent installationEvent)
        {
            try
            {
                _logger.LogInformation($"Mostrando notificación para: {installationEvent.Application.Name}");

                // Verificar si hay una sesión de usuario activa
                if (!await IsUserSessionActiveAsync())
                {
                    _logger.LogWarning("No hay sesión de usuario activa, no se puede mostrar notificación");
                    return;
                }

                var app = installationEvent.Application;
                
                // Crear el contenido de la notificación
                var title = $"🔍 Nueva Aplicación Detectada - {installationEvent.RiskLevel} Risk";
                var message = CreateInstallationMessage(installationEvent);

                // Mostrar notificación usando PowerShell para crear una ventana popup
                await ShowPopupNotificationAsync(title, message, installationEvent.RiskLevel);

                _logger.LogInformation($"Notificación mostrada exitosamente para {app.Name}");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error mostrando notificación para {installationEvent.Application.Name}");
            }
        }

        public async Task ShowCustomNotificationAsync(string title, string message, string iconType = "Info")
        {
            try
            {
                if (!await IsUserSessionActiveAsync())
                {
                    _logger.LogWarning("No hay sesión de usuario activa para mostrar notificación personalizada");
                    return;
                }

                await ShowPopupNotificationAsync(title, message, iconType);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error mostrando notificación personalizada");
            }
        }

        public async Task<bool> IsUserSessionActiveAsync()
        {
            try
            {
                // Verificar si hay una sesión de usuario activa
                var sessionId = WTSGetActiveConsoleSessionId();
                return sessionId != 0xFFFFFFFF; // 0xFFFFFFFF indica que no hay sesión activa
            }
            catch (Exception ex)
            {
                _logger.LogDebug(ex, "Error verificando sesión de usuario activa");
                return false;
            }
        }

        private string CreateInstallationMessage(InstallationEvent installationEvent)
        {
            var app = installationEvent.Application;
            var sb = new StringBuilder();

            // Información básica
            sb.AppendLine($"📱 APLICACIÓN: {app.Name}");
            sb.AppendLine($"📊 VERSIÓN: {app.Version}");
            sb.AppendLine($"🏢 PUBLISHER: {(!string.IsNullOrEmpty(app.Publisher) ? app.Publisher : "Desconocido")}");
            sb.AppendLine($"📅 DETECTADO: {installationEvent.Timestamp:dd/MM/yyyy HH:mm:ss}");
            sb.AppendLine();

            // Información de instalación
            if (!string.IsNullOrEmpty(app.InstallLocation))
                sb.AppendLine($"📂 UBICACIÓN: {app.InstallLocation}");
            
            if (!string.IsNullOrEmpty(app.EstimatedSize))
                sb.AppendLine($"💾 TAMAÑO: {app.EstimatedSize}");

            if (!string.IsNullOrEmpty(app.Architecture))
                sb.AppendLine($"🏗️ ARQUITECTURA: {app.Architecture}");

            sb.AppendLine();

            // Análisis de seguridad
            sb.AppendLine($"🛡️ NIVEL DE RIESGO: {installationEvent.RiskLevel}");
            
            if (installationEvent.SecurityFlags.Any())
            {
                sb.AppendLine("⚠️ ALERTAS DE SEGURIDAD:");
                foreach (var flag in installationEvent.SecurityFlags)
                {
                    sb.AppendLine($"   • {flag}");
                }
                sb.AppendLine();
            }

            // Recomendación
            if (!string.IsNullOrEmpty(installationEvent.RecommendedAction))
            {
                sb.AppendLine($"💡 RECOMENDACIÓN:");
                sb.AppendLine($"   {installationEvent.RecommendedAction}");
                sb.AppendLine();
            }

            // Información adicional
            if (!string.IsNullOrEmpty(app.Description))
                sb.AppendLine($"📝 DESCRIPCIÓN: {app.Description}");

            if (!string.IsNullOrEmpty(app.HelpLink))
                sb.AppendLine($"🔗 AYUDA: {app.HelpLink}");

            if (!string.IsNullOrEmpty(app.URLInfoAbout))
                sb.AppendLine($"🌐 INFO: {app.URLInfoAbout}");

            sb.AppendLine();
            sb.AppendLine("Esta notificación es solo informativa.");
            sb.AppendLine("Haga clic en 'Aceptar' para continuar.");

            return sb.ToString();
        }

        private async Task ShowPopupNotificationAsync(string title, string message, string riskLevel)
        {
            try
            {
                // Determinar el icono basado en el nivel de riesgo
                var iconType = riskLevel switch
                {
                    "Critical" => "Error",
                    "High" => "Warning",
                    "Medium" => "Warning",
                    _ => "Information"
                };

                // Crear script PowerShell para mostrar el popup
                var script = CreatePowerShellScript(title, message, iconType);
                
                // Ejecutar el script en el contexto del usuario
                await ExecutePowerShellScriptAsync(script);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error mostrando popup de notificación");
                
                // Fallback: intentar mostrar notificación del sistema
                try
                {
                    await ShowSystemNotificationAsync(title, message);
                }
                catch (Exception fallbackEx)
                {
                    _logger.LogError(fallbackEx, "Error en fallback de notificación");
                }
            }
        }

        private string CreatePowerShellScript(string title, string message, string iconType)
        {
            // Escapar comillas en el mensaje
            var escapedTitle = title.Replace("'", "''").Replace("`", "``");
            var escapedMessage = message.Replace("'", "''").Replace("`", "``");

            return $@"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Crear el formulario principal
$form = New-Object System.Windows.Forms.Form
$form.Text = '{escapedTitle}'
$form.Size = New-Object System.Drawing.Size(600, 500)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.TopMost = $true
$form.ShowInTaskbar = $true

# Establecer icono según el tipo
switch ('{iconType}') {{
    'Error' {{ $form.Icon = [System.Drawing.SystemIcons]::Error }}
    'Warning' {{ $form.Icon = [System.Drawing.SystemIcons]::Warning }}
    default {{ $form.Icon = [System.Drawing.SystemIcons]::Information }}
}}

# Crear panel principal
$panel = New-Object System.Windows.Forms.Panel
$panel.Dock = 'Fill'
$panel.Padding = New-Object System.Windows.Forms.Padding(20)
$form.Controls.Add($panel)

# Crear área de texto para el mensaje
$textBox = New-Object System.Windows.Forms.TextBox
$textBox.Multiline = $true
$textBox.ReadOnly = $true
$textBox.ScrollBars = 'Vertical'
$textBox.Text = '{escapedMessage}'
$textBox.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$textBox.Size = New-Object System.Drawing.Size(540, 380)
$textBox.Location = New-Object System.Drawing.Point(20, 20)
$textBox.BackColor = [System.Drawing.SystemColors]::Control
$textBox.BorderStyle = 'Fixed3D'
$panel.Controls.Add($textBox)

# Crear botón Aceptar
$buttonOK = New-Object System.Windows.Forms.Button
$buttonOK.Text = 'Aceptar'
$buttonOK.Size = New-Object System.Drawing.Size(100, 30)
$buttonOK.Location = New-Object System.Drawing.Point(250, 420)
$buttonOK.DialogResult = 'OK'
$buttonOK.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$panel.Controls.Add($buttonOK)

# Configurar el formulario
$form.AcceptButton = $buttonOK
$form.Add_Shown({{$form.Activate()}})

# Mostrar el formulario
$result = $form.ShowDialog()
$form.Dispose()
";
        }

        private async Task ExecutePowerShellScriptAsync(string script)
        {
            try
            {
                // Crear archivo temporal para el script
                var tempFile = Path.GetTempFileName() + ".ps1";
                await File.WriteAllTextAsync(tempFile, script, System.Text.Encoding.UTF8);

                // Configurar el proceso PowerShell
                var startInfo = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    Arguments = $"-ExecutionPolicy Bypass -WindowStyle Hidden -InputFormat Text -OutputFormat Text -File \"{tempFile}\"",
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    StandardOutputEncoding = System.Text.Encoding.UTF8,
                    StandardErrorEncoding = System.Text.Encoding.UTF8
                };

                // Ejecutar el script
                using var process = Process.Start(startInfo);
                if (process != null)
                {
                    await process.WaitForExitAsync();
                    
                    if (process.ExitCode != 0)
                    {
                        var error = await process.StandardError.ReadToEndAsync();
                        _logger.LogWarning($"PowerShell script terminó con código {process.ExitCode}: {error}");
                    }
                }

                // Limpiar archivo temporal
                try
                {
                    File.Delete(tempFile);
                }
                catch
                {
                    // Ignorar errores al eliminar archivo temporal
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error ejecutando script PowerShell");
                throw;
            }
        }

        private async Task ShowSystemNotificationAsync(string title, string message)
        {
            try
            {
                // Fallback usando msg.exe (comando del sistema)
                var truncatedMessage = message.Length > 500 ? message.Substring(0, 500) + "..." : message;
                
                var startInfo = new ProcessStartInfo
                {
                    FileName = "msg.exe",
                    Arguments = $"* /TIME:30 \"{title}: {truncatedMessage}\"",
                    UseShellExecute = false,
                    CreateNoWindow = true
                };

                using var process = Process.Start(startInfo);
                if (process != null)
                {
                    await process.WaitForExitAsync();
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error mostrando notificación del sistema");
            }
        }

        // Importar función de Windows API
        [DllImport("kernel32.dll")]
        private static extern uint WTSGetActiveConsoleSessionId();
    }
} 
