#!/usr/bin/env bash
# Installe la fonction fish `claude-docker` (+ abréviation `clauded`).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
FISH_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fish"

mkdir -p "$FISH_DIR/functions" "$FISH_DIR/conf.d"
ln -sf "$REPO_DIR/fish/claude-docker.fish" "$FISH_DIR/functions/claude-docker.fish"

cat > "$FISH_DIR/conf.d/claude-docker.fish" <<CONF
set -gx CLAUDE_DOCKER_REPO "$REPO_DIR"
abbr -a clauded claude-docker
CONF

echo "Installé. Ouvre un nouveau shell fish puis lance 'claude-docker' (ou 'clauded') dans un projet."
