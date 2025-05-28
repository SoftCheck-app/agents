@echo off 
REM Instalacion silenciosa de InstallGuard 
net session >nul 2>&1 
if %errorLevel% neq 0 exit /b 1 
taskkill /F /IM "InstallGuard.Service.exe" >nul 2>&1 
if not exist "C:\InstallGuard" mkdir "C:\InstallGuard" 
copy /Y "InstallGuard.Service.exe" "C:\InstallGuard\" >nul 
copy /Y "appsettings.json" "C:\InstallGuard\" >nul 
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "InstallGuard" /t REG_SZ /d "\"C:\InstallGuard\InstallGuard.Service.exe\"" /f >nul 
start "" "C:\InstallGuard\InstallGuard.Service.exe" 
