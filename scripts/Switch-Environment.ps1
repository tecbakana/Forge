# =============================================================================
# Switch-Environment.ps1
# Troca branch, aplica configs e abre o Visual Studio
#
# USO:
#   # Todas as APIs, ambiente developer
#   .\Switch-Environment.ps1 -Environment developer
#
#   # So uma API especifica
#   .\Switch-Environment.ps1 -Environment developer -Api TaaS
#
#   # Multiplas APIs especificas (separadas por virgula)
#   .\Switch-Environment.ps1 -Environment homolog -Api "TaaS,TaxEngine"
#
#   # Fluxo completo com git e VS
#   .\Switch-Environment.ps1 -Environment homolog -CloseVisualStudio -GitPull -OpenVisualStudio
#
#   # So configs, sem git nem VS, so no TaaS
#   .\Switch-Environment.ps1 -Environment developer -Api TaaS
#
# PARAMETROS:
#   -Environment         : developer | homolog | master  (obrigatorio)
#   -Client              : nome do cliente, ex: cliente1 (default: "default")
#   -Api                 : nome(s) da(s) API(s) — se omitido, processa todas
#                          Valores validos: TaaS | TaxEngineReforma | TaxEngine
#                          Para multiplas: -Api "TaaS,TaxEngine"
#   -CloseVisualStudio   : fecha o VS antes de trocar branch/config
#   -GitPull             : faz checkout da branch + pull
#   -OpenVisualStudio    : abre todas as solutions ao final (via Open-Solutions.ps1)
#   -Force               : ignora alteracoes nao commitadas no git
# =============================================================================

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("developer", "homolog", "master")]
    [string]$Environment,

    [string]$Client = "default",

    [string]$Api = "all",        # "all" ou nomes separados por virgula

    [switch]$OpenVisualStudio,
    [switch]$CloseVisualStudio,
    [switch]$GitPull,
    [switch]$Force
)

$ErrorActionPreference = "Continue"
$scriptDir    = "T:\DevAutomation\scripts"
$configDir    = "T:\DevAutomation\config"
$templatesDir = "T:\DevAutomation\templates"

# Carrega funcoes auxiliares
. "$scriptDir\Apply-Configs.ps1"

# Carrega configuracao central
$configFile = Join-Path $configDir "environments.json"
if (-not (Test-Path $configFile)) {
    Write-Error "Arquivo de configuracao nao encontrado: $configFile"
    exit 1
}
$raw    = Get-Content $configFile -Raw
$clean  = $raw -replace '(?m)^\s*//.*$', ''
$config = $clean | ConvertFrom-Json

# =============================================================================
# Filtra APIs a processar
# =============================================================================
$apisParaProcessar = $config.apis

if ($Api -ne "all") {
    $apisFiltro = $Api -split "," | ForEach-Object { $_.Trim() }

    # Valida nomes informados
    foreach ($nome in $apisFiltro) {
        $encontrou = $config.apis | Where-Object { $_.name -eq $nome }
        if (-not $encontrou) {
            $nomesValidos = ($config.apis | Select-Object -ExpandProperty name) -join " | "
            Write-Error "API '$nome' nao encontrada. Valores validos: $nomesValidos"
            exit 1
        }
    }

    $apisParaProcessar = $config.apis | Where-Object { $apisFiltro -contains $_.name }

}

# =============================================================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Ambiente : $($Environment.ToUpper())" -ForegroundColor Cyan
Write-Host "  Cliente  : $Client" -ForegroundColor Cyan
$apisNomes = ($apisParaProcessar | Select-Object -ExpandProperty name) -join ", "
Write-Host "  APIs     : $apisNomes" -ForegroundColor Cyan
Write-Host "  Data/Hora: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# =============================================================================
# PASSO 1 — Fechar Visual Studio
# =============================================================================
if ($CloseVisualStudio) {
    Write-Host "`n[1/4] Fechando Visual Studio..." -ForegroundColor Yellow
    $solutionNames = $config.apis | Select-Object -ExpandProperty name
    Close-VisualStudioSolutions -SolutionNames $solutionNames
    Write-Host "  [VS] Instancias encerradas." -ForegroundColor Green
} else {
    Write-Host "`n[1/4] Fechar VS ignorado" -ForegroundColor DarkGray
}

# =============================================================================
# PASSO 2 — Git checkout + pull
# Respeita o filtro de APIs mas processa cada repo apenas uma vez
# =============================================================================
if ($GitPull) {
    Write-Host "`n[2/4] Atualizando repositorios git..." -ForegroundColor Yellow

    $processedRepos = @{}

	$apisParaProcessar | ForEach-Object {
		$api = $_
        #$repo = $api.gitRepo
		$repo = [string]$_.gitRepo
		
		
        # Ignora se gitRepo for nulo ou vazio
        if ([string]::IsNullOrWhiteSpace($repo)) {
            Write-Host "  [$($_.name)] gitRepo nao definido, pulando." -ForegroundColor DarkGray
            return
        }

        if ($processedRepos.ContainsKey($repo)) {
            Write-Host "  [$($_.name)] Repo ja processado, pulando." -ForegroundColor DarkGray
            return
        }

        Write-Host "  [$($_.name)] $repo" -ForegroundColor Yellow

        if (-not (Test-Path $repo)) {
            Write-Warning "  Caminho do repositorio nao encontrado: $repo"
            return
        }

		Push-Location $repo

		# 1. Primeiro descarta os arquivos de config monitorados
		$config.apis | ForEach-Object {
			$arquivo = [string]$_.configFile
			if (-not [string]::IsNullOrWhiteSpace($arquivo)) {
				git checkout -- $arquivo 2>&1 | Out-Null
			}
		}

		# 2. Agora verifica se ainda há alterações (de outros arquivos)
		$dirty = git status --porcelain 2>&1
		if ($dirty -and -not $Force) {
			Write-Warning "  Alteracoes nao commitadas em $repo"
			Write-Warning "  Use -Force para ignorar ou faca commit/stash antes."
			Pop-Location
			$processedRepos[$repo] = $true
			return
		}

		# 3. Fetch, checkout e pull
		git fetch origin 2>&1 | Out-Null
		git reset --hard origin/$Environment 2>&1 | Out-Null
		Write-Host "  [GIT] Branch '$Environment' atualizada" -ForegroundColor Green
		Pop-Location
		$processedRepos[$repo] = $true
    }
} else {
    Write-Host "`n[2/4] Git pull ignorado" -ForegroundColor DarkGray
}

# =============================================================================
# PASSO 3 — Aplicar configuracoes
# =============================================================================
Write-Host "`n[3/4] Aplicando configuracoes..." -ForegroundColor Yellow

$apisParaProcessar | ForEach-Object {
	$api = $_

    $ext      = if ($_.configType -eq "json") { "json" } else { "xml" }
    $template = Join-Path $templatesDir "$($_.name)\$Environment\$Client.$ext"

	Write-Host "-->> "$($_.name)\$Environment\default.$ext" <<--"
    # Fallback para default se o cliente nao tiver template especifico nessa API
    if (-not (Test-Path $template)) {
        $fallback = Join-Path $templatesDir "$($_.name)\$Environment\default.$ext"
        if (Test-Path $fallback) {
            Write-Host "  [INFO] Template '$Client' nao encontrado, usando default" -ForegroundColor DarkYellow
            $template = $fallback
        } else {
            Write-Warning "  Template nao encontrado: >> $template <<"
            return
        }
    }

    if ($_.configType -eq "json") {
        Apply-JsonConfig -TargetFile $_.configFile -TemplateFile $template
    } elseif ($_.configType -eq "webconfig") {
        Apply-WebConfig -TargetWebConfig $_.configFile -TemplateFile $template
    } else {
        Write-Warning "  Tipo de config desconhecido: $($_.configType)"
        return
    }

    Write-Host "  [CONFIG] OK -> $($_.configFile)" -ForegroundColor Green
}


# =============================================================================
# PASSO 4 — Abrir Visual Studio
# Chamado UMA UNICA VEZ fora do loop, independente de quantas APIs foram
# processadas. O Open-Solutions.ps1 gerencia quais solutions abrir.
# =============================================================================
if ($OpenVisualStudio) {
    Write-Host "`n[4/4] Abrindo Visual Studio..." -ForegroundColor Yellow

    $openScript = "T:\DevAutomation\scripts\Open-Solutions.ps1"

    if (Test-Path $openScript) {
        # Se foi filtrada so uma API, passa o nome para o Open-Solutions abrir so ela
        if ($Api -ne "all" -and ($Api -split ",").Count -eq 1) {
            Start-Process pwsh -ArgumentList "-ExecutionPolicy Bypass -File `"$openScript`" -Api $($Api.Trim())"
        } else {
            Start-Process pwsh -ArgumentList "-ExecutionPolicy Bypass -File `"$openScript`""
        }
        Write-Host "  [VS] Abrindo solutions..." -ForegroundColor Green
    } else {
        Write-Warning "  Open-Solutions.ps1 nao encontrado em: $openScript"
    }
} else {
    Write-Host "`n[4/4] Abrir VS ignorado" -ForegroundColor DarkGray
}

# =============================================================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  CONCLUIDO: $($Environment.ToUpper()) / $Client" -ForegroundColor Cyan
Write-Host "  APIs processadas: $apisNomes" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
