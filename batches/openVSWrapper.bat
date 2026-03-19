@echo off
:: %1 = caminho do programa
:: %2 = índice da desktop (0=Desktop 1, 1=Desktop 2...)
:: %3 = caminho da solução

pwsh -NoProfile -ExecutionPolicy Bypass -File "T:\DevAutomation\scripts\Open-Solutions.ps1" -appPath "%~1" -DesktopIndex %2 -ProgramArgs %3