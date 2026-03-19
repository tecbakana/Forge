# =============================================================================
# Server-Operations.ps1
# Busca arquivos de configuracao de servidores remotos via UNC (\\servidor\C$)
# e salva como templates locais
# =============================================================================

function Invoke-ServerPullConfig {
    param(
        [string]$Environment,    # homolog | master
        [string]$Client,         # default | cliente1 ...
        [string]$ApiName,        # "all" ou nome especifico
        [string]$ConfigDir,
        [string]$TemplatesDir
    )

    $raw    = Get-Content (Join-Path $ConfigDir "environments.json") -Raw
    $clean  = $raw -replace '(?m)^\s*//.*$', ''
    $config = $clean | ConvertFrom-Json

    # Verifica se o ambiente tem servidor configurado
    $serverConfig = $config.servers.$Environment
    if (-not $serverConfig) {
        return @{ success = $false; error = "Nenhum servidor configurado para o ambiente '$Environment'" }
    }

    $host     = $serverConfig.host
    $user     = $serverConfig.user
    $password = $serverConfig.password
    $results  = @()

    # Conecta ao compartilhamento via net use
    Write-Host "  Conectando a $host..." -ForegroundColor DarkGray
    $netUse = net use $host /user:$user $password 2>&1
    if ($LASTEXITCODE -ne 0) {
        return @{ success = $false; error = "Falha ao conectar em $host : $netUse" }
    }

    try {
        $apisDoServidor = $serverConfig.apis
        if ($ApiName -ne "all") {
            $apisDoServidor = $apisDoServidor | Where-Object { $_.name -eq $ApiName }
        }

        foreach ($api in $apisDoServidor) {
            $uncPath = Join-Path $host $api.configPath
            $ext     = if ($api.configType -eq "json") { "json" } else { "xml" }

            # Destino local: templates\NomeApi\ambiente\cliente.ext
            $destDir  = Join-Path $TemplatesDir "$($api.name)\$Environment"
            $destFile = Join-Path $destDir "$Client.$ext"

            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }

            if (Test-Path $uncPath) {
                Copy-Item -Path $uncPath -Destination $destFile -Force
                Write-Host "  [OK] $($api.name) → $destFile" -ForegroundColor Green
                $results += @{ name = $api.name; success = $true; dest = $destFile }
            } else {
                Write-Warning "  [AVISO] Arquivo nao encontrado: $uncPath"
                $results += @{ name = $api.name; success = $false; error = "Nao encontrado: $uncPath" }
            }
        }
    } finally {
        # Sempre desconecta ao final
        net use $host /delete 2>&1 | Out-Null
        Write-Host "  Desconectado de $host" -ForegroundColor DarkGray
    }

    return @{ success = $true; results = $results }
}