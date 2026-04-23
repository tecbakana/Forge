@echo off
echo [DevPanel] Encerrando instancia anterior...
netsh http delete urlacl url=http://localhost:8080/ >nul 2>&1
taskkill /F /FI "IMAGENAME eq pwsh.exe" >nul 2>&1
timeout /t 2 /nobreak >nul
echo [DevPanel] Iniciando servidor...
echo [DevPanel] Acesse: http://localhost:8080
pwsh -ExecutionPolicy Bypass -File "%~dp0..\scripts\Start-Server.ps1"
pause