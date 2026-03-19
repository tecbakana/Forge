@echo off
:: ============================================================
:: go-developer.bat
:: Troca TODAS as APIs para o ambiente DEVELOPER
:: Fecha VS → git checkout developer + pull → aplica configs → abre VS
:: ============================================================
echo.
echo [DevAutomation] Iniciando troca para DEVELOPER...
echo.

pwsh -ExecutionPolicy Bypass -File "C:\DevAutomation\scripts\Switch-Environment.ps1" ^
  -Environment developer ^
  -CloseVisualStudio ^
  -GitPull ^
  -OpenVisualStudio

pause
