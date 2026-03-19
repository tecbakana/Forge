
# =============================================================================
# Carrega solutions do environments.json (sem hardcode)
# =============================================================================
$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptDir "..\config\environments.json"

$raw    = Get-Content $configPath -Raw -Encoding UTF8
$raw    = $raw -replace '(?m)//.*$', ''
$config = $raw | ConvertFrom-Json

# Monta lista unica de solutions (APIs que compartilham o mesmo .sln abrem apenas uma vez)
$seen      = @{}
$solutions = @()
foreach ($api in $config.apis) {
    if (-not $api.solutionPath) { continue }
    $slnKey = $api.solutionPath.ToLower()
    if ($seen.ContainsKey($slnKey)) { continue }
    $seen[$slnKey] = $true
    $solutions += @{ Name = $api.name; Sln = $api.solutionPath; Desktop = $api.desktop }
}

$vdExe  = Join-Path $scriptDir "..\tools\VirtualDesktop11.exe"

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

    if (Test-Path $vdExe) {
        & $vdExe /Switch:$($DesktopIndex - 1) 2>$null
        Start-Sleep -Milliseconds 700
        Write-Host "  Desktop $DesktopIndex ativada" -ForegroundColor DarkGray
    } else {
        Write-Warning "  VirtualDesktop11.exe nao encontrado em: $vdExe"
        Write-Host "  Mude manualmente para a Desktop $DesktopIndex e pressione qualquer tecla..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
}

#=================================================================
# função para testar se a aplicação já está aberta
#=================================================================
function Test-SolutionAberta {
    param([string]$SlnPath)

    $slnNome     = [System.IO.Path]::GetFileNameWithoutExtension($SlnPath)
    $slnPathNorm = $SlnPath.ToLower()

    # Metodo 1: verifica linha de comando via WMI
    $wmiProcs = Get-WmiObject Win32_Process -Filter "Name='devenv.exe'" -ErrorAction SilentlyContinue
    foreach ($w in $wmiProcs) {
        if ($w.CommandLine -and $w.CommandLine.ToLower() -like "*$slnPathNorm*") {
            return $true
        }
    }

    # Metodo 2: verifica titulo da janela (VS ja carregado)
    $processos = Get-Process -Name "devenv" -ErrorAction SilentlyContinue
    foreach ($p in $processos) {
        if ($p.MainWindowTitle -like "*$slnNome*") {
            return $true
        }
    }

    return $false
}


foreach ($sol in $solutions) {

    Write-Host ""
    Write-Host "→ $($sol.Name)" -ForegroundColor Yellow

    if (-not (Test-Path $sol.Sln)) {
        Write-Warning "  .sln nao encontrado: $($sol.Sln)"
        continue
    }
	
	if(-not (Test-SolutionAberta($sol.sln)))
	{
		Switch-ToDesktop -DesktopIndex $sol.Desktop
		Start-Sleep -Seconds 2
		Start-Process -FilePath $devenv -ArgumentList "`"$($sol.Sln)`""
		Start-Sleep -Seconds 2
		Write-Host "  [OK] Aberto" -ForegroundColor Green
	}

    #Start-Sleep -Seconds 3
}

Write-Host ""
Write-Host "=== Concluido ===" -ForegroundColor Cyan
Write-Host ""