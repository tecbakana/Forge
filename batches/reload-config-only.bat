@echo off
:: ============================================================
:: reload-config-only.bat
:: Reaplica SOMENTE os arquivos de configuracao
:: SEM fechar VS, SEM git pull, SEM abrir VS
::
:: Util quando:
::   - Voce editou um template e quer testar sem trocar branch
::   - Quer resetar as configs do ambiente atual
::
:: Edite o valor de ENVIRONMENT abaixo conforme necessario:
::   developer | homolog | master
:: ============================================================

set ENVIRONMENT=developer

echo.
echo [DevAutomation] Reaplicando configs do ambiente: %ENVIRONMENT%
echo.

pwsh -ExecutionPolicy Bypass -File "C:\DevAutomation\scripts\Switch-Environment.ps1" ^
  -Environment %ENVIRONMENT%

pause
