# Lance Claude Code dans le conteneur, avec le dossier courant comme projet.
# Équivalent PowerShell (Windows + Docker Desktop) de bin/claude-docker.
# Usage : claude-docker.ps1 [--rebuild] [--no-sudo] [arguments passés à claude...]
$ErrorActionPreference = 'Stop'

$RepoDir      = Split-Path -Parent $PSScriptRoot
$Image        = if ($env:CLAUDE_DOCKER_IMAGE) { $env:CLAUDE_DOCKER_IMAGE } else { 'claude-code' }
$ConfigVolume = if ($env:CLAUDE_DOCKER_CONFIG_VOLUME) { $env:CLAUDE_DOCKER_CONFIG_VOLUME } else { 'claude-config' }
$ToolsVolume  = if ($env:CLAUDE_DOCKER_TOOLS_VOLUME) { $env:CLAUDE_DOCKER_TOOLS_VOLUME } else { 'claude-tools' }
$ProjectDir   = (Get-Location).ProviderPath

$claudeArgs = @($args)
$rebuild = $false
$noSudo = $false
while ($claudeArgs.Count -gt 0 -and $claudeArgs[0] -in '--rebuild', '--no-sudo') {
    if ($claudeArgs[0] -eq '--rebuild') { $rebuild = $true } else { $noSudo = $true }
    $claudeArgs = @($claudeArgs | Select-Object -Skip 1)
}

# Construit l'image si absente (ou si --rebuild). Sous Windows, Docker Desktop
# gère les droits des montages : UID/GID par défaut (1000) du dockerfile.
docker image inspect $Image *> $null
if ($rebuild -or $LASTEXITCODE -ne 0) {
    $buildArgs = @('build')
    if ($rebuild) { $buildArgs += @('--no-cache', '--pull') }
    docker @buildArgs -t $Image -f (Join-Path $RepoDir 'dockerfile') $RepoDir
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
    '-v', "${ToolsVolume}:/home/dev/.local/share/mise",
    # Règles globales versionnées dans ce repo (lecture seule)
    '-v', "$(Join-Path $RepoDir 'config\CLAUDE.md'):/home/dev/.claude/CLAUDE.md:ro",
    '-v', "${ProjectDir}:${ContainerDir}",
    '-w', $ContainerDir,
    '--cap-drop', 'ALL',
    '--pids-limit', '4096'
)

if ($noSudo) {
    $dockerArgs += @('--security-opt', 'no-new-privileges', '-e', 'CLAUDE_DOCKER_NO_SUDO=1')
} else {
    # Seulement ce qu'il faut à sudo et apt
    foreach ($cap in 'CHOWN', 'DAC_OVERRIDE', 'FOWNER', 'FSETID', 'SETUID', 'SETGID', 'KILL', 'AUDIT_WRITE', 'NET_BIND_SERVICE') {
        $dockerArgs += @('--cap-add', $cap)
    }
}

# Pseudo-terminal seulement si on est dans un terminal
$dockerArgs += '-i'
if (-not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) {
    $dockerArgs += '-t'
}

$envFile = Join-Path $RepoDir '.env'
if (Test-Path $envFile) {
    $dockerArgs += @('--env-file', $envFile)
}

docker @dockerArgs $Image claude @claudeArgs
exit $LASTEXITCODE
