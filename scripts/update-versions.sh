#!/usr/bin/env bash
# Met à jour les versions fixées en tête du dockerfile : Claude Code, mise et
# les empreintes SHA-256 des binaires mise.
# Usage : scripts/update-versions.sh            écrit les nouvelles versions
#         scripts/update-versions.sh --check    n'écrit rien, sort en 1 s'il y en a
# CLAUDE_CHANNEL=stable suit le canal stable de Claude Code (défaut : latest).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCKERFILE="${DOCKERFILE:-$ROOT/dockerfile}"
CHANNEL="${CLAUDE_CHANNEL:-latest}"
CHECK=""
[[ "${1:-}" == "--check" ]] && CHECK=1

current() { sed -n "s/^ARG $1=//p" "$DOCKERFILE"; }
set_arg() {
    local tmp
    tmp="$(mktemp)"
    sed "s|^ARG $1=.*|ARG $1=$2|" "$DOCKERFILE" > "$tmp"
    cat "$tmp" > "$DOCKERFILE"
    rm -f "$tmp"
}
die() { echo "update-versions: $*" >&2; exit 2; }

# --- Claude Code
claude_new="$(curl -fsSL "https://downloads.claude.ai/claude-code-releases/$CHANNEL")" ||
    die "version de Claude Code introuvable (canal $CHANNEL)"
[[ "$claude_new" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version de Claude Code inattendue : $claude_new"

# --- mise : dernière release, puis ses empreintes
mise_url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/jdx/mise/releases/latest)" ||
    die "dernière release de mise introuvable"
mise_new="${mise_url##*/}"
[[ "$mise_new" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version de mise inattendue : $mise_new"

changed=0
report() { # <nom> <actuelle> <nouvelle>
    if [[ "$2" != "$3" ]]; then
        echo "$1 : $2 → $3"
        changed=1
    fi
}

claude_cur="$(current CLAUDE_VERSION)"
mise_cur="$(current MISE_VERSION)"
report "Claude Code" "$claude_cur" "$claude_new"
report "mise" "$mise_cur" "$mise_new"

if [[ "$changed" == 0 ]]; then
    echo "Versions à jour : Claude Code $claude_cur, mise $mise_cur"
    exit 0
fi
[[ -z "$CHECK" ]] || exit 1

if [[ "$mise_cur" != "$mise_new" ]]; then
    sums="$(curl -fsSL "https://github.com/jdx/mise/releases/download/$mise_new/SHASUMS256.txt")" ||
        die "empreintes de mise $mise_new introuvables"
    sum_of() {
        local s
        s="$(printf '%s\n' "$sums" | awk -v f="mise-$mise_new-linux-$1" '$2 == f || $2 == "./" f { print $1 }')"
        [[ "$s" =~ ^[0-9a-f]{64}$ ]] || die "empreinte de mise $mise_new linux-$1 introuvable"
        printf '%s\n' "$s"
    }
    amd64="$(sum_of x64)"
    arm64="$(sum_of arm64)"
    set_arg MISE_VERSION "$mise_new"
    set_arg MISE_SHA256_AMD64 "$amd64"
    set_arg MISE_SHA256_ARM64 "$arm64"
fi
[[ "$claude_cur" == "$claude_new" ]] || set_arg CLAUDE_VERSION "$claude_new"
