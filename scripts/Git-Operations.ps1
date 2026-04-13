# =============================================================================
# Git-Operations.ps1
# =============================================================================

function Get-GitStatus {
    param([string]$RepoPath)
    if (-not (Test-Path $RepoPath)) { return @{ error = "Caminho nao encontrado: $RepoPath" } }
    Push-Location $RepoPath

    $statusLines = git status --porcelain 2>&1
    $files = @()

    foreach ($line in $statusLines) {
        if (-not $line -or $line.Length -lt 3) { continue }
        $xy   = $line.Substring(0,2).Trim()
        $path = $line.Substring(3).Trim()
        $type = switch -Regex ($xy) {
            "^M"  { "modified" }
            "^A"  { "added" }
            "^D"  { "deleted" }
            "^R"  { "renamed" }
            "^\?" { "untracked" }
            default { $xy }
        }
        $diff = ""
        if ($type -eq "modified") {
            $diff = (git diff HEAD -- $path 2>&1) -join "`n"
        } elseif ($type -in @("added","untracked")) {
            if (Test-Path $path) { $diff = (Get-Content $path -Raw -ErrorAction SilentlyContinue) }
        }
        $files += @{ path = $path; type = $type; diff = $diff }
    }

    $rawB = git rev-parse --abbrev-ref HEAD 2>&1
    $branch = if ($rawB -and $rawB -isnot [System.Management.Automation.ErrorRecord]) { "$rawB".Trim() } else { "?" }
    Pop-Location
    return @{ branch = $branch; files = $files; count = $files.Count }
}

function Get-GitAheadBehind {
    param([string]$RepoPath)
    if (-not (Test-Path $RepoPath)) { return @{ error = "Caminho nao encontrado: $RepoPath" } }
    Push-Location $RepoPath

    $rawB = git rev-parse --abbrev-ref HEAD 2>&1
    $branch = if ($rawB -and $rawB -isnot [System.Management.Automation.ErrorRecord]) { "$rawB".Trim() } else { "?" }
    git fetch origin 2>&1 | Out-Null

    $ab     = git rev-list --left-right --count "origin/$branch...HEAD" 2>&1
    $ahead  = 0; $behind = 0
    if ($ab -match "(\d+)\s+(\d+)") { $behind = [int]$Matches[1]; $ahead = [int]$Matches[2] }

    $lastCommit = (git log -1 --format="%h — %s — %ar" 2>&1)
    Pop-Location

    return @{
        branch     = $branch
        ahead      = $ahead
        behind     = $behind
        lastCommit = "$lastCommit"
        status     = if ($ahead -eq 0 -and $behind -eq 0) { "synced" } elseif ($behind -gt 0) { "behind" } else { "ahead" }
    }
}

function Invoke-GitCommit {
    param([string]$RepoPath, [string]$Message)
    if (-not (Test-Path $RepoPath))              { return @{ success = $false; error = "Caminho nao encontrado" } }
    if ([string]::IsNullOrWhiteSpace($Message))  { return @{ success = $false; error = "Mensagem nao pode ser vazia" } }
    Push-Location $RepoPath
    try {
        git add -A 2>&1 | Out-Null
        $out = (git commit -m $Message 2>&1) -join "`n"
        Pop-Location
        return @{ success = $true; output = $out }
    } catch {
        Pop-Location
        return @{ success = $false; error = $_.Exception.Message }
    }
}

function Invoke-GitDiscard {
    param([string]$RepoPath)
    if (-not (Test-Path $RepoPath)) { return @{ success = $false; error = "Caminho nao encontrado" } }
    Push-Location $RepoPath
    try {
        git checkout -- . 2>&1 | Out-Null
        git clean -fd    2>&1 | Out-Null
        Pop-Location
        return @{ success = $true }
    } catch {
        Pop-Location
        return @{ success = $false; error = $_.Exception.Message }
    }
}