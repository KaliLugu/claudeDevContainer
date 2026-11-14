#!/usr/bin/env bash
# Installe la fonction bash `claude-docker` (+ alias `clauded`) via ~/.bashrc.
# Relançable sans risque : le bloc existant est remplacé.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BASHRC="${BASHRC:-$HOME/.bashrc}"
BEGIN="# >>> claude-docker >>>"
END="# <<< claude-docker <<<"

touch "$BASHRC"

# Retire un éventuel bloc précédent (ex. si le repo a été déplacé)
if grep -qF "$BEGIN" "$BASHRC"; then
    tmp="$(mktemp)"
    sed "/^$BEGIN\$/,/^$END\$/d" "$BASHRC" > "$tmp"
    cat "$tmp" > "$BASHRC"
    rm -f "$tmp"
fi

{
    echo "$BEGIN"
    printf 'export CLAUDE_DOCKER_REPO=%q\n' "$REPO_DIR"
    echo 'source "$CLAUDE_DOCKER_REPO/bash/claude-docker.bash"'
    echo "$END"
} >> "$BASHRC"

echo "Installé dans $BASHRC. Lance 'source $BASHRC' (ou ouvre un nouveau shell) puis 'claude-docker' (ou 'clauded') dans un projet."
