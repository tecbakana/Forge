# =============================================================================
# Start-DevPanel.ps1
# Servidor HTTP local que serve a interface web e expõe a mini API REST
#
# USO:
#   .\Start-DevPanel.ps1              → sobe na porta 8080 e abre o browser
#   .\Start-DevPanel.ps1 -Port 9090   → porta customizada
#   .\Start-DevPanel.ps1 -NoBrowser   → não abre o browser automaticamente
#
# ENDPOINTS expostos:
#   GET  /              → serve o index.html
#   GET  /api/config    → retorna environments.json
#   GET  /api/status    → retorna branch atual de cada repo + cliente ativo
#   POST /api/switch    → executa Switch-Environment.ps1
#   GET  /api/template  → lê um arquivo de template
#   POST /api/template  → salva um arquivo de template
# =============================================================================

param(
    [int]    $Port      = 8080,
    [switch] $NoBrowser
)

$ErrorActionPreference = "Stop"
$rootDir      = Split-Path $PSScriptRoot -Parent
$scriptDir    = $PSScriptRoot
$panelDir     = Join-Path $rootDir "panel"
$configDir    = Join-Path $rootDir "config"
$templatesDir = Join-Path $rootDir "templates"
$switchScript = Join-Path $PSScriptRoot "Switch-Environment.ps1"
$devreqDir    = Join-Path $rootDir "dev-requests"

# Arquivo de estado: guarda o último cliente aplicado por API
$stateFile    = Join-Path $configDir "state.json"

. (Join-Path $PSScriptRoot "Git-Operations.ps1")
. (Join-Path $PSScriptRoot "Server-Operations.ps1")

# Dot-source
. (Join-Path $PSScriptRoot "Invoke-GeminiAgent.ps1")

# =============================================================================
# Helpers
# =============================================================================

function Get-State {
    if (Test-Path $stateFile) {
        return Get-Content $stateFile -Raw | ConvertFrom-Json -AsHashtable
    }
    return @{}
}

function Set-State($key, $value) {
    $s = Get-State
    $s[$key] = $value
    $s | ConvertTo-Json | Set-Content $stateFile -Encoding UTF8
}

function Write-Response {
    param($Context, $Body, [string]$ContentType = "application/json", [int]$StatusCode = 200)
    $response = $Context.Response
    $response.StatusCode = $StatusCode
    $response.ContentType = $ContentType
    $response.Headers.Add("Access-Control-Allow-Origin", "*")
    $response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    $response.Headers.Add("Access-Control-Allow-Headers", "Content-Type")
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $response.ContentLength64 = $bytes.Length
    $response.OutputStream.Write($bytes, 0, $bytes.Length)
    $response.OutputStream.Close()
}

function Read-Body($Context) {
    $reader = New-Object System.IO.StreamReader($Context.Request.InputStream)
    return $reader.ReadToEnd()
}

function Json($obj) { $obj | ConvertTo-Json -Depth 10 -Compress }

# =============================================================================
# Handlers
# =============================================================================

function Handle-Agent($ctx) {
    $body    = Read-Body $ctx | ConvertFrom-Json -AsHashtable
    $message = $body["message"]
    $history = if ($body["history"]) { $body["history"] } else { @() }

    # Lê config
    $raw      = Get-Content (Join-Path $configDir "environments.json") -Raw
    $clean    = $raw -replace '(?m)^\s*//.*$', ''
    $config   = $clean | ConvertFrom-Json
    $apiKey   = $config.agent.apiKey
    $model    = $config.agent.model
	$url      = $config.agent.url

    # Lê estado atual
    $state    = Get-State
    $apiNames = ($config.apis | ForEach-Object { $_.name }) -join ", "

    # Contexto do sistema para o Gemini
    $systemCtx = @"
Você é um assistente de ambiente de desenvolvimento chamado DevAgent.
Responda sempre em português brasileiro, de forma concisa e direta.

ESTADO ATUAL:
- APIs disponíveis: $apiNames
- Estado: $($state | ConvertTo-Json -Compress)

REGRAS:
- Ao executar ações, confirme o que foi feito de forma resumida
- Se o usuário pedir algo ambíguo, pergunte antes de executar
- Caso você tenha dúvidas na execução, pergunte antes de executar
- Para switch de ambiente sem especificar APIs, use all
- Nunca invente dados — use sempre as ferramentas para buscar informações reais
"@

    # 1. Chama o Gemini
    $geminiResp = Invoke-GeminiAgent `
        -Message       $message `
        -ApiKey        $apiKey `
        -Model         $model `
            -Url         $url `
        -History       $history `
        -SystemContext $systemCtx
    Write-Host "teste $($url)$($model)"
    if ($geminiResp.type -eq "error") {
        Write-Response $ctx (Json @{ type = "error"; text = $geminiResp.error })
        return
    }

    # 2. É uma tool call?
    if ($geminiResp.type -eq "toolCall") {
        $toolName = $geminiResp.name
        $args     = $geminiResp.args
        $result   = $null

        switch ($toolName) {
            "switch_environment" {
                $envArg     = $args.environment
                $clientArg  = if ($args.client)      { $args.client }      else { "default" }
                $apisArg    = if ($args.apis)         { $args.apis }        else { "all" }
                $pullArg    = if ($args.gitPull)      { "-GitPull" }        else { "" }
                $openArg    = if ($args.openVS)       { "-OpenVisualStudio" }  else { "" }
                $closeArg   = if ($args.closeVS)      { "-CloseVisualStudio" } else { "" }
                $forceArg   = if ($args.force)        { "-Force" }          else { "" }

                $cmd = "& '$switchScript' -Environment '$envArg' -Client '$clientArg' -Api '$apisArg' $pullArg $openArg $closeArg $forceArg"
                $out = Invoke-Expression $cmd 2>&1
                $result = @{ output = ($out -join "`n") }
            }
            "get_git_status" {
                $api    = $config.apis | Where-Object { $_.name -eq $args.api } | Select-Object -First 1
                $result = Get-GitStatus -RepoPath $api.gitRepo
            }
            "get_git_ahead_behind" {
                $result = @()
                $config.apis | ForEach-Object {
                    $ab = Get-GitAheadBehind -RepoPath $_.gitRepo
                    $result += @{ name = $_.name; aheadBehind = $ab }
                }
            }
            "list_branches" {
                $api    = $config.apis | Where-Object { $_.name -eq $args.api } | Select-Object -First 1
                $result = Get-GitBranches -RepoPath $api.gitRepo
            }
            "get_current_status" {
                $result = $state
            }
        }

        # 3. Manda resultado de volta para o Gemini gerar resposta final
        $historyAtual = $history + @(
            @{ role = "user";  parts = @(@{ text = $message }) },
            @{ role = "model"; parts = @(@{ functionCall = @{ name = $toolName; args = $args } }) }
        )

        $finalResp = Send-GeminiToolResult `
            -ApiKey        $apiKey `
            -Model         $model `
            -Url         $url `
            -History       $historyAtual `
            -ToolName      $toolName `
            -ToolResult    $result `
            -SystemContext $systemCtx

        Write-Response $ctx (Json @{
            type   = "text"
            text   = $finalResp.text
            action = $toolName
        })
        return
    }
    Write-Host "  [AGENT] Enviando para Gemini: $($body | ConvertTo-Json -Depth 5 -Compress)" -ForegroundColor DarkGray
    # 4. Resposta direta em texto
    Write-Response $ctx (Json @{ type = "text"; text = $geminiResp.text })
}

function Handle-DevRequests($ctx) {
    $method = $ctx.Request.HttpMethod

    # POST — cria novo arquivo individual em devreqDir
    if ($method -eq "POST") {
        $body = Read-Body $ctx | ConvertFrom-Json -AsHashtable
        $id   = [guid]::NewGuid().ToString()
        $now  = [datetime]::UtcNow.ToString("o")
        $item = @{
            id                  = $id
            api                 = $body["api"]
            tipo                = $body["tipo"]
            impacto             = $body["impacto"]
            descricao           = $body["descricao"]
            detalhes            = $body["detalhes"]
            url_externa         = $body["url_externa"]
            diretorio_alvo      = $body["diretorio_alvo"]
            status              = "pendente"
            resultado           = $null
            prompt_agente       = $null
            timestamp           = $now
            timestamp_atualizacao = $now
        }
        $path = Join-Path $devreqDir "$id.json"
        $item | ConvertTo-Json -Depth 10 | Set-Content $path -Encoding UTF8
        Write-Response $ctx (Json @{ success = $true; id = $id })
        return
    }

    # GET — lê queue.json dos repos + arquivos individuais em devreqDir
    $raw    = Get-Content (Join-Path $configDir "environments.json") -Raw
    $config = ($raw -replace '(?m)^\s*//.*$','') | ConvertFrom-Json

    $todas  = [System.Collections.Generic.List[object]]::new()
    $seen   = @{}
    $idsVia = [System.Collections.Generic.HashSet[string]]::new()

    # Arquivos individuais em devreqDir
    if (Test-Path $devreqDir) {
        Get-ChildItem $devreqDir -Filter "*.json" | ForEach-Object {
            try {
                $content = Get-Content $_.FullName -Raw
                if ([string]::IsNullOrWhiteSpace($content)) { return }
                $item = $content | ConvertFrom-Json -AsHashtable
                if (-not $item -or -not $item["id"]) { return }
                $idsVia.Add($item["id"]) | Out-Null
                $todas.Add($item)
            } catch {
                Write-Warning "  [DEV-REQUEST] Erro ao ler $($_.Name): $_"
            }
        }
    }

    # queue.json dos repos (compatibilidade com Salematic e outros)
    if ($config -and $config.apis) {
        foreach ($apiDef in $config.apis) {
            $repo    = "$($apiDef.gitRepo)"
            $apiName = "$($apiDef.name)"
            if ([string]::IsNullOrWhiteSpace($repo) -or $seen.ContainsKey($repo)) { continue }
            $seen[$repo] = $true

            $queuePath = Join-Path $repo "dev-requests\queue.json"
            if (-not (Test-Path $queuePath)) { continue }

            try {
                $content = Get-Content $queuePath -Raw
                if ([string]::IsNullOrWhiteSpace($content)) { continue }
                $items = $content | ConvertFrom-Json -AsHashtable
                if (-not $items) { continue }
                @($items) | ForEach-Object {
                    if (-not $_ -or $idsVia.Contains($_["id"])) { return }
                    $_["api"] = $apiName
                    $todas.Add($_)
                }
            } catch {
                Write-Warning "  [DEV-REQUEST] Erro ao ler $queuePath`: $_"
            }
        }
    }

    Write-Response $ctx (ConvertTo-Json -InputObject @($todas.ToArray()) -Depth 10 -Compress)
}

function Find-DevRequestItem($id) {
    # Tenta arquivo individual primeiro
    $filePath = Join-Path $script:devreqDir "$id.json"
    if (Test-Path $filePath) {
        $content = Get-Content $filePath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
        return @{ item = $content; type = "file"; path = $filePath; items = $null; queuePath = $null }
    }

    # Fallback: queue.json dos repos
    $raw    = Get-Content (Join-Path $script:configDir "environments.json") -Raw
    $config = ($raw -replace '(?m)^\s*//.*$','') | ConvertFrom-Json
    foreach ($apiDef in $config.apis) {
        $repo = "$($apiDef.gitRepo)"
        if ([string]::IsNullOrWhiteSpace($repo)) { continue }
        $queuePath = Join-Path $repo "dev-requests\queue.json"
        if (-not (Test-Path $queuePath)) { continue }
        $items = Get-Content $queuePath -Raw | ConvertFrom-Json -AsHashtable
        $item  = @($items) | Where-Object { $_["id"] -eq $id } | Select-Object -First 1
        if ($item) {
            return @{ item = $item; type = "queue"; path = $null; items = $items; queuePath = $queuePath }
        }
    }
    return $null
}

function Save-DevRequestItem($found) {
    $now = [datetime]::UtcNow.ToString("o")
    $found["item"]["timestamp_atualizacao"] = $now
    if ($found["type"] -eq "file") {
        $found["item"] | ConvertTo-Json -Depth 10 | Set-Content $found["path"] -Encoding UTF8
    } else {
        $found["items"] | ConvertTo-Json -Depth 10 | Set-Content $found["queuePath"] -Encoding UTF8
    }
}

function Handle-DevRequestAction($ctx) {
    $body   = Read-Body $ctx | ConvertFrom-Json -AsHashtable
    $id     = $body["id"]
    $action = $body["action"]
    $api    = $body["api"]

    $found = Find-DevRequestItem $id
    if (-not $found) {
        Write-Response $ctx (Json @{ success = $false; error = "Request não encontrada" }) -StatusCode 404
        return
    }
    $item = $found.item

    $novoStatus = switch ($action) {
        "ignorar"   { "cancelado" }
        "cancelar"  { "cancelado" }
        "aprovar"   { "in_progress" }
        "retomar"   { "in_progress" }
        "completar" { "done" }
        default     { "in_progress" }
    }
    $item["status"] = $novoStatus
    Save-DevRequestItem $found

    if ($action -eq "implementar" -or $action -eq "aprovar" -or $action -eq "retomar") {
        $raw    = Get-Content (Join-Path $script:configDir "environments.json") -Raw
        $config = ($raw -replace '(?m)^\s*//.*$','') | ConvertFrom-Json
        $apiName = if ($item["api"]) { $item["api"] } else { $api }
        $apiObj = $config.apis | Where-Object { $_.name -eq $apiName } | Select-Object -First 1
        $repoPath = if ($apiObj) { "$($apiObj.gitRepo)" } else { $rootDir }

        $devreqFilePath = Join-Path $script:devreqDir "$id.json"
        $respostaUsuario = if ($item["resposta_usuario"]) { "`n`nResposta do usuario: $($item["resposta_usuario"])" } else { "" }

        $prompt = "Voce esta implementando uma dev-request do Forge. " +
            "Arquivo da demanda: $devreqFilePath `n" +
            "Descricao: $($item["descricao"]). " +
            "Tipo: $($item["tipo"]). Impacto: $($item["impacto"]). " +
            "Detalhes: $($item["detalhes"]).$respostaUsuario `n`n" +
            "INSTRUCOES OBRIGATORIAS: " +
            "1) Ao terminar, atualize o campo 'status' para 'done' e 'resultado' com resumo do que foi feito no arquivo $devreqFilePath. " +
            "2) SE tiver duvidas ou blockers ANTES de implementar, atualize o campo 'status' para 'impeditivo' e escreva sua duvida no campo 'resultado' do arquivo $devreqFilePath — NAO use 'done' quando houver duvidas. " +
            "3) Atualize sempre o campo 'timestamp_atualizacao' com a data/hora atual UTC no formato ISO 8601."

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName               = "claude"
        $psi.Arguments              = "--dangerously-skip-permissions --print"
        $psi.WorkingDirectory       = $repoPath
        $psi.RedirectStandardInput  = $true
        $psi.RedirectStandardOutput = $false
        $psi.RedirectStandardError  = $false
        $psi.UseShellExecute        = $false
        $psi.CreateNoWindow         = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $proc.StandardInput.WriteLine($prompt)
        $proc.StandardInput.Close()
        Write-Host "  [DEV-REQUEST] Claude Code despachado (background) para: $($item["descricao"])" -ForegroundColor Cyan
    }

    Write-Response $ctx (Json @{ success = $true; status = $novoStatus })
}

function Handle-DevRequestResponder($ctx) {
    try {
        $body     = Read-Body $ctx | ConvertFrom-Json -AsHashtable
        $id       = $body["id"]
        $resposta = $body["resposta"]

        $filePath = Join-Path $script:devreqDir "$id.json"
        if (-not (Test-Path $filePath)) {
            Write-Response $ctx (Json @{ success = $false; error = "Arquivo não encontrado: $filePath" }) -StatusCode 404
            return
        }

        $content = Get-Content $filePath -Raw -Encoding UTF8
        $item    = $content | ConvertFrom-Json -AsHashtable
        $item["resposta_usuario"]      = $resposta
        $item["timestamp_atualizacao"] = [datetime]::UtcNow.ToString("o")

        $item | ConvertTo-Json -Depth 10 | Set-Content $filePath -Encoding UTF8

        Write-Response $ctx (Json @{ success = $true })
    } catch {
        Write-Warning "  [RESPONDER] Erro: $_"
        Write-Response $ctx (Json @{ success = $false; error = $_.ToString() }) -StatusCode 500
    }
}

function Handle-Restart($ctx) {
    Write-Response $ctx (Json @{ success = $true; message = "Reiniciando..." })
    Start-Process pwsh -ArgumentList "-ExecutionPolicy Bypass -File `"$(Join-Path $PSScriptRoot 'Start-DevPanel.ps1')`""
    Stop-Process -Id $PID
}


function Handle-ServerPullConfig($ctx) {
    $body   = Read-Body $ctx | ConvertFrom-Json -AsHashtable
    $env    = $body["environment"]
    $client = if ($body["client"]) { $body["client"] } else { "default" }
    $api    = if ($body["api"])    { $body["api"] }    else { "all" }

    Write-Host "  [SERVER] Pull config: $env / $client / $api" -ForegroundColor DarkGray

    $result = Invoke-ServerPullConfig `
        -Environment  $env `
        -Client       $client `
        -ApiName      $api `
        -ConfigDir    $configDir `
        -TemplatesDir $templatesDir

    Write-Response $ctx (Json $result)
}

function Handle-Config($ctx) {
    $configFile = Join-Path $configDir "environments.json"
    # Remove linhas de comentário do JSON antes de retornar
    $raw = Get-Content $configFile -Raw
    $clean = $raw -replace '(?m)^\s*//.*$', ''
    Write-Response $ctx $clean
}

function Handle-Status($ctx) {
    $raw    = Get-Content (Join-Path $configDir "environments.json") -Raw
    $clean  = $raw -replace '(?m)^\s*//.*$', ''
    $config = $clean | ConvertFrom-Json

    $state  = Get-State
    $result = @()
    $processedRepos = @{}

    $config.apis | ForEach-Object {
        $api  = $_
        $nome = [string]$api.name
        $repo = [string]$api.gitRepo

        $branch = "?"
        if (-not [string]::IsNullOrWhiteSpace($repo) -and -not $processedRepos.ContainsKey($repo)) {
            try {
                Push-Location $repo
                $raw = git rev-parse --abbrev-ref HEAD 2>$null
                $branch = if ($raw -and $raw -isnot [System.Management.Automation.ErrorRecord]) { "$raw".Trim() } else { "?" }
                Pop-Location
            } catch {
                $branch = "?"
            }
            $processedRepos[$repo] = $branch
        } elseif ($processedRepos.ContainsKey($repo)) {
            $branch = $processedRepos[$repo]
        }

        $cliente = if ($state -and $state.ContainsKey($nome)) { $state[$nome] } else { "default" }

        $result += @{
            name   = $nome
            branch = $branch
            client = $cliente
        }
    }

    Write-Response $ctx (Json @(,$result))
}

function Handle-Switch($ctx) {
    $body = Read-Body $ctx | ConvertFrom-Json -AsHashtable

    $env     = $body["environment"]
    $client  = if ($body["client"]) { $body["client"] } else { "default" }
    $api     = if ($body["api"] -and $body["api"] -ne "all") { $body["api"] } else { "all" }
    $gitP    = $body["gitPull"]           -eq $true
    $openVS  = $body["openVisualStudio"]  -eq $true
    $closeVS = $body["closeVisualStudio"] -eq $true

    # Monta argumentos para o Switch-Environment.ps1 (sem -OpenVisualStudio, tratado aqui)
    $switchArgs = @("-Environment", $env, "-Client", $client)
    if ($api -ne "all") { $switchArgs += @("-Api", $api) }
    if ($gitP)    { $switchArgs += "-GitPull" }
    if ($closeVS) { $switchArgs += "-CloseVisualStudio" }

    try {
        $output = & powershell.exe -ExecutionPolicy Bypass -File $switchScript @switchArgs 2>&1
        $messages = $output | ForEach-Object { $_.ToString() }

        # Salva estado: registra cliente aplicado por API
        $configRaw  = Get-Content (Join-Path $configDir "environments.json") -Raw
        $configClean = $configRaw -replace '(?m)^\s*//.*$', ''
        $configObj  = $configClean | ConvertFrom-Json
        foreach ($cfgApi in $configObj.apis) {
            Set-State $cfgApi.name $client
        }

        # Abre Visual Studio diretamente daqui (evita cadeia de processos aninhados)
        $logFile = Join-Path $rootDir "vs-open.log"
        "[$([datetime]::Now)] Handle-Switch: openVS=$openVS  api=$api" | Out-File $logFile -Append
        if ($openVS) {
            $openScript = Join-Path $PSScriptRoot "Open-Solutions.ps1"
            "[$([datetime]::Now)] Iniciando Open-Solutions.ps1 com api=$api" | Out-File $logFile -Append
            $vsArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $openScript)
            if ($api -ne "all") { $vsArgs += @("-Api", $api) }
            "[$([datetime]::Now)] vsArgs: $($vsArgs -join ' ')" | Out-File $logFile -Append
            Start-Process pwsh -ArgumentList $vsArgs
            "[$([datetime]::Now)] Start-Process pwsh disparado" | Out-File $logFile -Append
        }

        Write-Response $ctx (Json @{ success = $true; messages = $messages })
    } catch {
        Write-Response $ctx (Json @{ success = $false; error = $_.Exception.Message }) -StatusCode 500
    }
}

function Handle-GetTemplate($ctx) {
    $query  = $ctx.Request.QueryString
    $apiName = $query["api"]
    $env     = $query["env"]
    $client  = if ($query["client"]) { $query["client"] } else { "default" }

    # Determina extensão pelo configType da API
    $configFile = Join-Path $configDir "environments.json"
    $raw   = Get-Content $configFile -Raw
    $clean = $raw -replace '(?m)^\s*//.*$', ''
    $config = $clean | ConvertFrom-Json
    $api = $config.apis | Where-Object { $_.name -eq $apiName }

    $ext  = if ($api.configType -eq "json") { "json" } else { "xml" }
    $path = Join-Path $templatesDir "$apiName\$env\$client.$ext"

    if (Test-Path $path) {
        $content = Get-Content $path -Raw
        Write-Response $ctx (Json @{ content = $content; path = $path })
    } else {
        Write-Response $ctx (Json @{ content = ""; path = $path; notFound = $true })
    }
}

function Handle-SaveTemplate($ctx) {
    $body    = Read-Body $ctx | ConvertFrom-Json -AsHashtable
    $apiName = $body["api"]
    $env     = $body["env"]
    $client  = if ($body["client"]) { $body["client"] } else { "default" }
    $content = $body["content"]

    $configFile = Join-Path $configDir "environments.json"
    $raw   = Get-Content $configFile -Raw
    $clean = $raw -replace '(?m)^\s*//.*$', ''
    $config = $clean | ConvertFrom-Json
    $api = $config.apis | Where-Object { $_.name -eq $apiName }

    $ext     = if ($api.configType -eq "json") { "json" } else { "xml" }
    $dir     = Join-Path $templatesDir "$apiName\$env"
    $path    = Join-Path $dir "$client.$ext"

    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    Set-Content -Path $path -Value $content -Encoding UTF8
    Write-Response $ctx (Json @{ success = $true; path = $path })
}

function Handle-Browse($ctx) {
    $query = $ctx.Request.QueryString
    $type  = if ($query["type"]) { $query["type"] } else { "folder" }

    Add-Type -AssemblyName System.Windows.Forms | Out-Null

    $selected = $null

    if ($type -eq "file") {
        $filter = if ($query["filter"]) { $query["filter"] } else { "All files (*.*)|*.*" }
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Filter = $filter
        $dialog.Title  = "Selecionar arquivo"
        $result = $dialog.ShowDialog()
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            $selected = $dialog.FileName
        }
    } else {
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = "Selecionar pasta"
        $result = $dialog.ShowDialog()
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            $selected = $dialog.SelectedPath
        }
    }

    if ($selected) {
        Write-Response $ctx (Json @{ path = $selected })
    } else {
        Write-Response $ctx (Json @{ path = $null; cancelled = $true })
    }
}

function Handle-Static($ctx) {
    $urlPath  = $ctx.Request.Url.AbsolutePath
    $filePath = if ($urlPath -eq "/") { Join-Path $panelDir "index.html" }
                else                  { Join-Path $panelDir $urlPath.TrimStart('/') }

    if (Test-Path $filePath) {
        $mime = switch ([System.IO.Path]::GetExtension($filePath)) {
            ".html" { "text/html; charset=utf-8" }
            ".js"   { "application/javascript" }
            ".css"  { "text/css" }
            ".jpg"  { "image/jpeg" }
            ".jpeg" { "image/jpeg" }
            ".png"  { "image/png" }
            ".svg"  { "image/svg+xml" }
            ".ico"  { "image/x-icon" }
            default { "text/plain" }
        }
        $content = Get-Content $filePath -Raw
        Write-Response $ctx $content -ContentType $mime
    } else {
        Write-Response $ctx "Not Found" -StatusCode 404 -ContentType "text/plain"
    }
}

# — NOVO: no bloco de handlers —

function Handle-GitStatus($ctx) {
    $query   = $ctx.Request.QueryString
    $apiName = $query["api"]
    $raw     = Get-Content (Join-Path $configDir "environments.json") -Raw
    $config  = ($raw -replace '(?m)^\s*//.*$','') | ConvertFrom-Json

    $results = @()
    $processedRepos = @{}

    $config.apis | ForEach-Object {
        $api  = $_
        $repo = "$($api.gitRepo)"
        if ([string]::IsNullOrWhiteSpace($repo)) { return }
        if ($apiName -and $api.name -ne $apiName) { return }
        if ($processedRepos.ContainsKey($repo)) {
            $results += @{ name = $api.name; repo = $repo; skipped = $true }
            return
        }
        $processedRepos[$repo] = $true
        $status = Get-GitStatus -RepoPath $repo
        $results += @{ name = $api.name; repo = $repo; status = $status }
    }

    Write-Response $ctx (Json @(,$results))
}

function Handle-GitAheadBehind($ctx) {
    $raw    = Get-Content (Join-Path $configDir "environments.json") -Raw
    $config = ($raw -replace '(?m)^\s*//.*$','') | ConvertFrom-Json

    $results = @()
    $processedRepos = @{}

    $config.apis | ForEach-Object {
        $api  = $_
        $repo = "$($api.gitRepo)"
        if ([string]::IsNullOrWhiteSpace($repo)) { return }
        if ($processedRepos.ContainsKey($repo)) { return }
        $processedRepos[$repo] = $true
        $ab = Get-GitAheadBehind -RepoPath $repo
        $results += @{ name = $api.name; repo = $repo; aheadBehind = $ab }
    }

    Write-Response $ctx (Json $results)
}

function Handle-GitCommit($ctx) {
    $body    = Read-Body $ctx | ConvertFrom-Json -AsHashtable
    $apiName = $body["api"]
    $message = $body["message"]

    $raw    = Get-Content (Join-Path $configDir "environments.json") -Raw
    $config = ($raw -replace '(?m)^\s*//.*$','') | ConvertFrom-Json

    $results = @()
    $config.apis | ForEach-Object {
        $api  = $_
        $repo = "$($api.gitRepo)"
        if ([string]::IsNullOrWhiteSpace($repo)) { return }
        if ($api.name -ne $apiName) { return }
        $result = Invoke-GitCommit -RepoPath $repo -Message $message
        $results += @{ name = $api.name; result = $result }
    }

    Write-Response $ctx (Json @{ success = $true; results = $results })
}

function Handle-GitDiscard($ctx) {
    $body    = Read-Body $ctx | ConvertFrom-Json -AsHashtable
    $apiName = $body["api"]

    $raw    = Get-Content (Join-Path $configDir "environments.json") -Raw
    $config = ($raw -replace '(?m)^\s*//.*$','') | ConvertFrom-Json

    $config.apis | ForEach-Object {
        $api  = $_
        $repo = "$($api.gitRepo)"
        if ([string]::IsNullOrWhiteSpace($repo)) { return }
        if ($api.name -ne $apiName) { return }
        Invoke-GitDiscard -RepoPath $repo | Out-Null
    }

    Write-Response $ctx (Json @{ success = $true })
}

# =============================================================================
# Handle-RegisterApp / Handle-UnregisterApp
# =============================================================================

function Handle-RegisterApp($ctx) {
    $body = Read-Body $ctx | ConvertFrom-Json -AsHashtable

    $cfgFile = Join-Path $configDir "environments.json"
    $raw     = Get-Content $cfgFile -Raw
    $clean   = $raw -replace '(?m)^\s*//.*$', ''
    $config  = $clean | ConvertFrom-Json

    # Valida nome duplicado
    $existe = $config.apis | Where-Object { $_.name -eq $body["name"] }
    if ($existe) {
        Write-Response $ctx (Json @{ success = $false; error = "API '$($body["name"])' ja cadastrada." }) -StatusCode 400
        return
    }

    # Monta novo objeto
    $novaApi = [ordered]@{
        name         = $body["name"]
        configType   = $body["configType"]
        configFile   = $body["configFile"]
        gitRepo      = $body["gitRepo"]
        solutionPath = $body["solutionPath"]
        desktop      = [int]$body["desktop"]
        batchOpen    = Join-Path $rootDir "batches\open-solution.bat"
        clients      = @("default")
    }

    # Adiciona ao array e salva
    $lista = [System.Collections.Generic.List[object]]($config.apis)
    $lista.Add([pscustomobject]$novaApi)
    $config.apis = $lista.ToArray()
    $config | ConvertTo-Json -Depth 10 | Set-Content $cfgFile -Encoding UTF8

    # Cria estrutura de templates
    $ext = if ($body["configType"] -eq "json") { "json" } else { "xml" }
    foreach ($env in @("developer", "homolog", "master")) {
        $dir = Join-Path $templatesDir "$($body["name"])\$env"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $defaultFile = Join-Path $dir "default.$ext"
        if (-not (Test-Path $defaultFile)) {
            if ($ext -eq "json") { "{}" | Set-Content $defaultFile -Encoding UTF8 }
            else { "<configuration><appSettings></appSettings><connectionStrings></connectionStrings></configuration>" | Set-Content $defaultFile -Encoding UTF8 }
        }
    }

    Write-Host "  [APP] Cadastrada: $($body["name"])" -ForegroundColor Green
    Write-Response $ctx (Json @{ success = $true })
}

function Handle-UnregisterApp($ctx) {
    $body = Read-Body $ctx | ConvertFrom-Json -AsHashtable
    $nome = $body["name"]

    $cfgFile = Join-Path $configDir "environments.json"
    $raw     = Get-Content $cfgFile -Raw
    $clean   = $raw -replace '(?m)^\s*//.*$', ''
    $config  = $clean | ConvertFrom-Json

    $config.apis = @($config.apis | Where-Object { $_.name -ne $nome })
    $config | ConvertTo-Json -Depth 10 | Set-Content $cfgFile -Encoding UTF8

    # Remove pasta de templates
    $templateDir = Join-Path $templatesDir $nome
    if (Test-Path $templateDir) {
        Remove-Item $templateDir -Recurse -Force
    }

    Write-Host "  [APP] Removida: $nome" -ForegroundColor Yellow
    Write-Response $ctx (Json @{ success = $true })
}

# =============================================================================
# Router principal
# =============================================================================

function Route($ctx) {
    $method = $ctx.Request.HttpMethod
    $path   = $ctx.Request.Url.AbsolutePath

    # Preflight CORS
    if ($method -eq "OPTIONS") {
        Write-Response $ctx "" -StatusCode 204
        return
    }

    switch -Regex ($path) {
        "^/api/config$"    { Handle-Config   $ctx }
        "^/api/status$"    { Handle-Status   $ctx }
        "^/api/switch$"    { Handle-Switch   $ctx }
        "^/api/template$"  {
            if ($method -eq "GET")  { Handle-GetTemplate  $ctx }
            else                    { Handle-SaveTemplate $ctx }
        }
		"^/api/git/status$"      { Handle-GitStatus      $ctx }
		"^/api/git/aheadbehind$" { Handle-GitAheadBehind $ctx }
		"^/api/git/commit$"      { Handle-GitCommit       $ctx }
		"^/api/git/discard$"     { Handle-GitDiscard      $ctx }
		"^/api/server/pullconfig$" { Handle-ServerPullConfig $ctx }
		"^/api/restart$"         { Handle-Restart         $ctx }
		"^/api/agent$"           { Handle-Agent           $ctx }
		"^/api/apps/register$"      { Handle-RegisterApp      $ctx }
		"^/api/apps/unregister$"    { Handle-UnregisterApp    $ctx }
		"^/api/browse$"             { Handle-Browse           $ctx }
		"^/api/devrequests$"           { Handle-DevRequests         $ctx }
		"^/api/devrequests/action$"    { Handle-DevRequestAction    $ctx }
		"^/api/devrequests/responder$" { Handle-DevRequestResponder $ctx }
        default                  { Handle-Static          $ctx }
    }
}

# =============================================================================
# Start
# =============================================================================

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DevPanel rodando em:" -ForegroundColor Cyan
Write-Host "  http://localhost:$Port" -ForegroundColor Green
Write-Host "  Ctrl+C para encerrar" -ForegroundColor DarkGray
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if (-not $NoBrowser) {
    Start-Process "http://localhost:$Port"
}

try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()  # bloqueia até chegar request
        try   { Route $ctx }
        catch { Write-Warning "Erro ao processar request: $_" }
    }
} finally {
    $listener.Stop()
    Write-Host "Servidor encerrado." -ForegroundColor DarkGray
}
