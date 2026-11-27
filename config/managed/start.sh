#!/usr/bin/env bash
# Commande lancée dans le conteneur par claude-docker : prépare la session,
# puis démarre Claude avec les arguments reçus.
if [ -n "${CLAUDE_AGENTS_REPOS:-}" ]; then
    bash /etc/claude-code/agents-sync.sh ||
        echo "claude-docker: synchronisation des repos d'agents en échec (ignorée)" >&2
fi
exec claude "$@"
