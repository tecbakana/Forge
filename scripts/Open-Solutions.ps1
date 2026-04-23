param(
    [string]$Api = "all"   # "all" ou nomes separados por virgula
)

$rootDir = Split-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) -Parent
$logFile = Join-Path $rootDir "vs-open.log"
"[$([datetime]::Now)] Open-Solutions.ps1 INICIADO — Api=$Api  PSVersion=$($PSVersionTable.PSVersion)" | Out-File $logFile -Append

# Sanitiza $Api: se for um objeto serializado (@{name=...}), extrai o nome
if ($Api -match '^\@\{name=([^;}\s]+)') {
    $Api = $Matches[1]
    "[$([datetime]::Now)] AVISO: Api recebido como objeto serializado — corrigido para: '$Api'" | Out-File $logFile -Append
}

# =============================================================================
# Carrega solutions do environments.json (sem hardcode)
# =============================================================================
$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptDir "..\config\environments.json"

"[$([datetime]::Now)] configPath=$configPath  existe=$(Test-Path $configPath)" | Out-File $logFile -Append

$raw    = Get-Content $configPath -Raw -Encoding UTF8
$raw    = $raw -replace '(?m)^\s*//.*$', ''
$config = $raw | ConvertFrom-Json

# Filtra APIs conforme parametro -Api
$apisFiltradas = $config.apis
"[$([datetime]::Now)] Total APIs no config: $($config.apis.Count) — nomes: $(($config.apis | ForEach-Object { $_.name }) -join ', ')" | Out-File $logFile -Append
if ($Api -ne "all") {
    $apisFiltro = $Api -split "," | ForEach-Object { $_.Trim() }
    "[$([datetime]::Now)] Filtro aplicado: $($apisFiltro -join ', ')" | Out-File $logFile -Append
    $apisFiltradas = @($config.apis | Where-Object { $apisFiltro -contains $_.name })
}
"[$([datetime]::Now)] APIs filtradas: $($apisFiltradas.Count) — $($apisFiltradas | ForEach-Object { $_.name } | Join-String -Separator ', ')" | Out-File $logFile -Append

# Monta lista unica de solutions (APIs que compartilham o mesmo .sln abrem apenas uma vez)
$seen      = @{}
$solutions = @()
foreach ($entry in $apisFiltradas) {
    "[$([datetime]::Now)] Verificando $($entry.name) — solutionPath='$($entry.solutionPath)'" | Out-File $logFile -Append
    if (-not $entry.solutionPath) {
        "[$([datetime]::Now)] SKIP $($entry.name): solutionPath vazio" | Out-File $logFile -Append
        continue
    }
    $slnKey = $entry.solutionPath.ToLower()
    if ($seen.ContainsKey($slnKey)) {
        "[$([datetime]::Now)] SKIP $($entry.name): sln duplicado" | Out-File $logFile -Append
        continue
    }
    $seen[$slnKey] = $true
    $solutions += @{ Name = $entry.name; Sln = $entry.solutionPath; Desktop = $entry.desktop }
}

"[$([datetime]::Now)] Solutions encontradas: $($solutions.Count) — $($solutions | ForEach-Object { $_.Name } | Join-String -Separator ', ')" | Out-File $logFile -Append

$vdExe  = Join-Path $scriptDir "..\tools\VirtualDesktop11.exe"
"[$([datetime]::Now)] vdExe=$vdExe  existe=$(Test-Path $vdExe)" | Out-File $logFile -Append

$devenv = $null
$candidatos = @(
    "T:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\IDE\devenv.exe",
    "T:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\devenv.exe",
    "T:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\IDE\devenv.exe"
)
foreach ($c in $candidatos) {
    if (Test-Path $c) { $devenv = $c; break }
}
"[$([datetime]::Now)] devenv=$devenv" | Out-File $logFile -Append
if (-not $devenv) {
    "[$([datetime]::Now)] ERRO: devenv.exe nao encontrado" | Out-File $logFile -Append
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
    "[$([datetime]::Now)] Processando: $($sol.Name) — sln=$($sol.Sln)" | Out-File $logFile -Append

    if (-not (Test-Path $sol.Sln)) {
        Write-Warning "  .sln nao encontrado: $($sol.Sln)"
        "[$([datetime]::Now)] SKIP: .sln nao encontrado: $($sol.Sln)" | Out-File $logFile -Append
        continue
    }

    $jaAberta = Test-SolutionAberta -SlnPath $sol.Sln
    "[$([datetime]::Now)] Test-SolutionAberta=$jaAberta" | Out-File $logFile -Append

    if (-not $jaAberta) {
        "[$([datetime]::Now)] Chamando Switch-ToDesktop desktop=$($sol.Desktop)" | Out-File $logFile -Append
        Switch-ToDesktop -DesktopIndex $sol.Desktop
        Start-Sleep -Seconds 2
        "[$([datetime]::Now)] Chamando Start-Process devenv com '$($sol.Sln)'" | Out-File $logFile -Append
        Start-Process -FilePath $devenv -ArgumentList "`"$($sol.Sln)`""
        Start-Sleep -Seconds 2
        "[$([datetime]::Now)] Start-Process devenv disparado para $($sol.Name)" | Out-File $logFile -Append
        Write-Host "  [OK] Aberto" -ForegroundColor Green
    } else {
        "[$([datetime]::Now)] SKIP: $($sol.Name) ja esta aberta" | Out-File $logFile -Append
    }
}

Write-Host ""
Write-Host "=== Concluido ===" -ForegroundColor Cyan
Write-Host ""