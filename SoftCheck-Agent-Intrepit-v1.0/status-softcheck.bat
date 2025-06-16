@echo off
echo ========================================
echo    ESTADO SOFTCHECK AGENT
echo ========================================
echo.

echo Verificando estado del servicio...
echo.

sc query "SoftCheck Agent" 2>nul
if %errorLevel% neq 0 (
    echo El servicio SoftCheck Agent NO esta instalado.
) else (
    echo.
    echo Detalles del servicio:
    sc qc "SoftCheck Agent"
)

echo.
echo ========================================
pause 