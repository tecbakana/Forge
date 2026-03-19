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
$scriptDir    = "T:\DevAutomation\scripts"
$panelDir     = "T:\DevAutomation\panel"
$configDir    = "T:\DevAutomation\config"
$templatesDir = "T:\DevAutomation\templates"
$switchScript = "T:\DevAutomation\scripts\Switch-Environment.ps1"

# Arquivo de estado: guarda o último cliente aplicado por API
$stateFile    = "T:\DevAutomation\config\state.json"

. "T:\DevAutomation\scripts\Git-Operations.ps1"
. "T:\DevAutomation\scripts\Server-Operations.ps1"

# Dot-source
. "T:\DevAutomation\scripts\Invoke-GeminiAgent.ps1"

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

function Handle-Restart($ctx) {
    Write-Response $ctx (Json @{ success = $true; message = "Reiniciando..." })
    Start-Process pwsh -ArgumentList "-ExecutionPolicy Bypass -File `"T:\DevAutomation\scripts\Start-DevPanel.ps1`""
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
            Push-Location $repo
            $branch = (git rev-parse --abbrev-ref HEAD 2>$null).Trim()
            Pop-Location
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

    # Monta argumentos para o Switch-Environment.ps1
    $args = @("-Environment", $env, "-Client", $client)
    if ($api -ne "all") { $args += @("-Api", $api) }
    if ($gitP)    { $args += "-GitPull" }
    if ($openVS)  { $args += "-OpenVisualStudio" }
    if ($closeVS) { $args += "-CloseVisualStudio" }

    try {
        $output = & powershell.exe -ExecutionPolicy Bypass -File $switchScript @args 2>&1
        $messages = $output | ForEach-Object { $_.ToString() }

        # Salva estado: registra cliente aplicado por API
        $configFile = Join-Path $configDir "environments.json"
        $raw   = Get-Content $configFile -Raw
        $clean = $raw -replace '(?m)^\s*//.*$', ''
        $config = $clean | ConvertFrom-Json
        foreach ($api in $config.apis) {
            Set-State $api.name $client
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

function Handle-Static($ctx) {
    $urlPath  = $ctx.Request.Url.AbsolutePath
    $filePath = if ($urlPath -eq "/") { Join-Path $panelDir "index.html" }
                else                  { Join-Path $panelDir $urlPath.TrimStart('/') }

    if (Test-Path $filePath) {
        $mime = switch ([System.IO.Path]::GetExtension($filePath)) {
            ".html" { "text/html; charset=utf-8" }
            ".js"   { "application/javascript" }
            ".css"  { "text/css" }
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
		"^/api/restart$" { Handle-Restart $ctx }
		"^/api/agent$" { Handle-Agent $ctx }
        default            { Handle-Static $ctx }
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
