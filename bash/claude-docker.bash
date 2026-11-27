# Lance Claude Code dans le conteneur avec le dossier courant comme projet.
# Sourcé depuis ~/.bashrc par install-bash.sh ; CLAUDE_DOCKER_REPO pointe vers ce repo.
claude-docker() {
    if [[ -z "${CLAUDE_DOCKER_REPO:-}" ]]; then
        echo "claude-docker: CLAUDE_DOCKER_REPO n'est pas défini" >&2
        return 1
    fi
    "$CLAUDE_DOCKER_REPO/bin/claude-docker" "$@"
}

alias clauded=claude-docker
