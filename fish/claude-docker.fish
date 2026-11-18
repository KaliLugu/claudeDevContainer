# Lance Claude Code dans le conteneur avec le dossier courant comme projet.
# Le repo est déduit de l'emplacement réel de ce fichier (suivi du lien
# installé par install-fish.sh) ; CLAUDE_DOCKER_REPO permet de le forcer.
set -l __claude_docker_file (realpath (status --current-filename) 2>/dev/null)
if not set -q CLAUDE_DOCKER_REPO; and test -n "$__claude_docker_file"
    set -gx CLAUDE_DOCKER_REPO (dirname (dirname $__claude_docker_file))
end

function claude-docker --description 'Claude Code dans Docker, projet = dossier courant'
    if not set -q CLAUDE_DOCKER_REPO; or not test -x $CLAUDE_DOCKER_REPO/bin/claude-docker
        echo "claude-docker: repo introuvable, lance install-fish.sh ou définis CLAUDE_DOCKER_REPO" >&2
        return 1
    end
    $CLAUDE_DOCKER_REPO/bin/claude-docker $argv
end
