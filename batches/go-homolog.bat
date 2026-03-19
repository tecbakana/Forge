@echo off
:: ============================================================
:: go-homolog.bat
:: Troca TODAS as APIs para o ambiente HOMOLOG
:: Uso típico: atender chamado ou testar em homolog rapidamente
:: ============================================================
echo.
echo [DevAutomation] Iniciando troca para HOMOLOG...
echo.

pwsh -ExecutionPolicy Bypass -File "C:\DevAutomation\scripts\Switch-Environment.ps1" ^
  -Environment homolog ^
  -CloseVisualStudio ^
  -GitPull ^
  -OpenVisualStudio

pause
