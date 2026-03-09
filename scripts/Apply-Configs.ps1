# =============================================================================
# Apply-Configs.ps1
# Funcoes auxiliares para aplicar configuracoes nos arquivos de cada API
# =============================================================================

# -----------------------------------------------------------------------------
# Aplica configuracoes em Web.config (apenas appSettings e connectionStrings)
# Faz merge cirurgico — nao substitui o arquivo inteiro, preserva o restante
# -----------------------------------------------------------------------------
function Apply-WebConfig {
    param(
        [string]$TargetWebConfig,
        [string]$TemplateFile
    )

    if (-not (Test-Path $TargetWebConfig)) {
        Write-Warning "    Web.config nao encontrado: $TargetWebConfig"
        return
    }
    if (-not (Test-Path $TemplateFile)) {
        Write-Warning "    Template nao encontrado: $TemplateFile"
        return
    }

    [xml]$target   = Get-Content $TargetWebConfig -Encoding UTF8
    [xml]$template = Get-Content $TemplateFile    -Encoding UTF8

    # === appSettings ===
    $targetAppSettings   = $target.SelectSingleNode("//appSettings")
    $templateAppSettings = $template.SelectSingleNode("//appSettings")

    if ($templateAppSettings -and $targetAppSettings) {
        foreach ($addNode in $templateAppSettings.SelectNodes("add")) {
            $key      = $addNode.GetAttribute("key")
            $existing = $targetAppSettings.SelectSingleNode("add[@key='$key']")

            if ($existing) {
                $existing.SetAttribute("value", $addNode.GetAttribute("value"))
            } else {
                $imported = $target.ImportNode($addNode, $true)
                $targetAppSettings.AppendChild($imported) | Out-Null
            }
        }
        $count = $templateAppSettings.SelectNodes("add").Count
        Write-Host "    [appSettings] $count chaves aplicadas" -ForegroundColor DarkGray
    }

    # === connectionStrings ===
    $targetConnStrings   = $target.SelectSingleNode("//connectionStrings")
    $templateConnStrings = $template.SelectSingleNode("//connectionStrings")

    if ($templateConnStrings -and $targetConnStrings) {
        foreach ($addNode in $templateConnStrings.SelectNodes("add")) {
            $name     = $addNode.GetAttribute("name")
            $existing = $targetConnStrings.SelectSingleNode("add[@name='$name']")

            if ($existing) {
                $existing.SetAttribute("connectionString", $addNode.GetAttribute("connectionString"))
                if ($addNode.GetAttribute("providerName")) {
                    $existing.SetAttribute("providerName", $addNode.GetAttribute("providerName"))
                }
            } else {
                $imported = $target.ImportNode($addNode, $true)
                $targetConnStrings.AppendChild($imported) | Out-Null
            }
        }
        $count = $templateConnStrings.SelectNodes("add").Count
        Write-Host "    [connectionStrings] $count entradas aplicadas" -ForegroundColor DarkGray
    }

    # Salva preservando encoding e indentacao
    $settings             = New-Object System.Xml.XmlWriterSettings
    $settings.Indent      = $true
    $settings.IndentChars = "  "
    $settings.Encoding    = [System.Text.Encoding]::UTF8

    $writer = [System.Xml.XmlWriter]::Create($TargetWebConfig, $settings)
    $target.Save($writer)
    $writer.Close()
}

# -----------------------------------------------------------------------------
# Aplica configuracoes em appsettings.json
# Substitui o arquivo inteiro pelo template — sem merge
# O template deve ser o appsettings.json completo do ambiente/cliente
# -----------------------------------------------------------------------------
function Apply-JsonConfig {
    param(
        [string]$TargetFile,
        [string]$TemplateFile
    )

    if (-not (Test-Path $TargetFile)) {
        Write-Warning "    appsettings.json nao encontrado: $TargetFile"
        return
    }
    if (-not (Test-Path $TemplateFile)) {
        Write-Warning "    Template nao encontrado: $TemplateFile"
        return
    }

    Copy-Item -Path $TemplateFile -Destination $TargetFile -Force

    Write-Host "    [appsettings.json] substituido pelo template" -ForegroundColor DarkGray
}

# -----------------------------------------------------------------------------
# Fecha instancias do Visual Studio que correspondem as solutions gerenciadas
# CloseMainWindow = fecha gentilmente (pergunta sobre arquivos nao salvos)
# Se nao fechar em 15s, forca Kill
# -----------------------------------------------------------------------------
function Close-VisualStudioSolutions {
    param([string[]]$SolutionNames)

    $vsProcesses = Get-Process -Name "devenv" -ErrorAction SilentlyContinue

    if (-not $vsProcesses) {
        Write-Host "  [VS] Nenhuma instancia aberta." -ForegroundColor DarkGray
        return
    }

    foreach ($proc in $vsProcesses) {
        $title = $proc.MainWindowTitle
        $match = $SolutionNames | Where-Object { $title -like "*$_*" }

        if ($match) {
            Write-Host "  [VS] Fechando: $title" -ForegroundColor DarkGray
            $proc.CloseMainWindow() | Out-Null
            $proc.WaitForExit(15000)

            if (-not $proc.HasExited) {
                Write-Warning "  VS nao fechou no tempo esperado, forcando encerramento..."
                $proc.Kill()
            }
        }
    }

    Start-Sleep -Seconds 2
}
