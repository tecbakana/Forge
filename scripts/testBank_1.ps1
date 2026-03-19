
# =============================================================================
# Definicao das solutions
# =============================================================================
$solutions = @(
    @{
        Name    = "TaaS"
        Sln     = "T:\Developer\RepositorioTrabalho\Systax2025\TAAS\TaaS.sln"
        Desktop = 2
    },
    @{
        Name    = "TaxEngineReforma"
        Sln     = "T:\Developer\RepositorioTrabalho\Systax2025\TaxEngineReforma\TaxEngineReforma.sln"
        Desktop = 3
    },
    @{
        Name    = "TaxEngine"
        Sln     = "T:\Developer\RepositorioTrabalho\Systax2025\TaxEngine\TaxEngineService\TaxEngine.sln"
        Desktop = 4
    }
)

$devenv = $null
$candidatos = @(
    "T:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\IDE\devenv.exe",
    "T:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\devenv.exe",
    "T:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\IDE\devenv.exe"
)
foreach ($c in $candidatos) {
    if (Test-Path $c) { $devenv = $c; break }
}
if (-not $devenv) {
    Write-Error "devenv.exe nao encontrado. Verifique a instalacao do Visual Studio 2022."
    exit 1
}


function Switch-ToDesktop {
    param([int]$DesktopIndex)

    $vdExe = "T:\DevAutomation\tools\VirtualDesktop11.exe"

    if (Test-Path $vdExe) {
        & $vdExe /Switch:$($DesktopIndex - 1) 2>$null
        Start-Sleep -Milliseconds 700
        Write-Host "  Desktop $DesktopIndex ativada" -ForegroundColor DarkGray
    } else {
        Write-Warning "  VirtualDesktop11.exe nao encontrado em T:\DevAutomation\tools\"
        Write-Host "  Mude manualmente para a Desktop $DesktopIndex e pressione qualquer tecla..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
}


foreach ($sol in $solutions) {

    Write-Host ""
    Write-Host "→ $($sol.Name)" -ForegroundColor Yellow

    if (-not (Test-Path $sol.Sln)) {
        Write-Warning "  .sln nao encontrado: $($sol.Sln)"
        continue
    }

    Switch-ToDesktop -DesktopIndex $sol.Desktop
    Start-Sleep -Seconds 2
    Start-Process -FilePath $devenv -ArgumentList "`"$($sol.Sln)`""
	Start-Sleep -Seconds 2
    Write-Host "  [OK] Aberto" -ForegroundColor Green

    #Start-Sleep -Seconds 3
}

Write-Host ""
Write-Host "=== Concluido ===" -ForegroundColor Cyan
Write-Host ""