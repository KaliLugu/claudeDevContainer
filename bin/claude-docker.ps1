# Lance Claude Code dans le conteneur, avec le dossier courant comme projet.
# Équivalent PowerShell (Windows + Docker Desktop) de bin/claude-docker.
# Usage : claude-docker.ps1 [--rebuild] [arguments passés à claude...]
$ErrorActionPreference = 'Stop'

$RepoDir      = Split-Path -Parent $PSScriptRoot
$Image        = if ($env:CLAUDE_DOCKER_IMAGE) { $env:CLAUDE_DOCKER_IMAGE } else { 'claude-code' }
$ConfigVolume = if ($env:CLAUDE_DOCKER_CONFIG_VOLUME) { $env:CLAUDE_DOCKER_CONFIG_VOLUME } else { 'claude-config' }
$ProjectDir   = (Get-Location).ProviderPath

$claudeArgs = @($args)
$rebuild = $false
if ($claudeArgs.Count -gt 0 -and $claudeArgs[0] -eq '--rebuild') {
    $rebuild = $true
    $claudeArgs = @($claudeArgs | Select-Object -Skip 1)
}

# Construit l'image si absente (ou si --rebuild). Sous Windows, Docker Desktop
# gère les droits des montages : UID/GID par défaut (1000) du dockerfile.
docker image inspect $Image *> $null
if ($rebuild -or $LASTEXITCODE -ne 0) {
    docker build -t $Image -f (Join-Path $RepoDir 'dockerfile') $RepoDir
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

# C:\Users\moi\projet -> /c/Users/moi/projet : chemin stable par projet dans le
# conteneur, pour que l'historique Claude reste distinct par projet.
if ($ProjectDir -notmatch '^([A-Za-z]):\\') {
    Write-Error "Dossier non supporté (lecteur local attendu) : $ProjectDir"
}
$ContainerDir = '/' + $Matches[1].ToLower() + ($ProjectDir.Substring(2) -replace '\\', '/')
$ContainerDir = $ContainerDir.TrimEnd('/')
if ($ContainerDir -eq '') { $ContainerDir = '/' }

$name = 'claude-' + ((Split-Path -Leaf $ProjectDir) -replace '[^a-zA-Z0-9_.-]', '-') + "-$PID"

$dockerArgs = @(
    'run', '--rm',
    '--name', $name,
    '-v', "${ConfigVolume}:/home/dev/.claude",
    # Règles globales versionnées dans ce repo (lecture seule)
    '-v', "$(Join-Path $RepoDir 'config\CLAUDE.md'):/home/dev/.claude/CLAUDE.md:ro",
    # Agents spécialisés : écrits par Claude, versionnés dans ce repo
    '-v', "$(Join-Path $RepoDir 'agents'):/home/dev/.claude/agents",
    '-v', "${ProjectDir}:${ContainerDir}",
    '-w', $ContainerDir
)

# Mode interactif seulement si on est dans un terminal
if (-not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) {
    $dockerArgs += '-it'
}

$envFile = Join-Path $RepoDir '.env'
if (Test-Path $envFile) {
    $dockerArgs += @('--env-file', $envFile)
}

docker @dockerArgs $Image claude @claudeArgs
exit $LASTEXITCODE
