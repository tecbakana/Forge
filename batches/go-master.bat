@echo off
:: ============================================================
:: go-master.bat
:: Troca TODAS as APIs para o ambiente MASTER
:: ============================================================
echo.
echo [DevAutomation] Iniciando troca para MASTER...
echo.

pwsh -ExecutionPolicy Bypass -File "C:\DevAutomation\scripts\Switch-Environment.ps1" ^
  -Environment master ^
  -CloseVisualStudio ^
  -GitPull ^
  -OpenVisualStudio

pause
