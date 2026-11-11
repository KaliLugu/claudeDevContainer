# Lance Claude Code dans le conteneur avec le dossier courant comme projet.
# Installé par install-fish.sh ; CLAUDE_DOCKER_REPO pointe vers ce repo.
function claude-docker --description 'Claude Code dans Docker, projet = dossier courant'
    if not set -q CLAUDE_DOCKER_REPO
        echo "claude-docker: CLAUDE_DOCKER_REPO n'est pas défini" >&2
        return 1
    end
    $CLAUDE_DOCKER_REPO/bin/claude-docker $argv
end
