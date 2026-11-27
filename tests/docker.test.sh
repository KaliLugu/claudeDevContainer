#!/usr/bin/env bash
# Tests de bout en bout : construit l'image et lance le conteneur comme le
# ferait un utilisateur. Image et volumes de test, supprimés à la fin.
# Usage : tests/docker.test.sh            (nécessite Docker)
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
export CLAUDE_DOCKER_IMAGE="claude-code-test-$$"
export CLAUDE_DOCKER_CONFIG_VOLUME="claude-config-test-$$"
export CLAUDE_DOCKER_TOOLS_VOLUME="claude-tools-test-$$"
IMG=$CLAUDE_DOCKER_IMAGE

cleanup() {
    docker images --format '{{.Repository}}:{{.Tag}}' | grep "^$IMG" | xargs -r docker image rm -f >/dev/null 2>&1
    docker volume rm "$CLAUDE_DOCKER_CONFIG_VOLUME" "$CLAUDE_DOCKER_TOOLS_VOLUME" >/dev/null 2>&1
    rm -rf "$TMP"
}
trap cleanup EXIT

fail=0
n=0
ok() { # <description> <commande...>
    local what=$1; shift
    n=$((n + 1))
    if ! "$@" >"$TMP/out" 2>&1; then
        fail=$((fail + 1))
        echo "ÉCHEC  $what"
        tail -n 15 "$TMP/out" | sed 's/^/    /'
    fi
}
no() { local what=$1; shift; ok "$what" not "$@"; }
not() { ! "$@"; }
launch() { (cd "$TMP/proj" && bash "$ROOT/bin/claude-docker" "$@"); }
out_has() { local o; o="$("${@:2}" 2>&1)"; printf '%s\n' "$o" | grep -F -- "$1" >/dev/null; }
in_image() { docker run --rm "$@"; }

mkdir -p "$TMP/proj"

# L'image se construit même quand le GID de l'hôte existe déjà dans Debian
# (20 = staff sur macOS, dialout dans l'image)
ok "build avec UID 501 / GID 20 (macOS)" \
    docker build -q --build-arg UID=501 --build-arg GID=20 -t "$IMG-macos" -f "$ROOT/dockerfile" "$ROOT"
ok "utilisateur dev en 501:20" out_has "501:20" in_image "$IMG-macos" sh -c 'echo "$(id -u):$(id -g)"'

ok "premier lancement : build et claude --version" out_has "Claude Code" launch --version
no "deuxième lancement : pas de rebuild" out_has "naming to" launch --version
ok "l'entrée par pipe ne bloque pas" sh -c "echo bonjour | (cd '$TMP/proj' && bash '$ROOT/bin/claude-docker' --version)"
ok "--no-sudo accepté avant les arguments de claude" out_has "Claude Code" launch --no-sudo --version

CAPS="--cap-drop ALL --cap-add CHOWN --cap-add DAC_OVERRIDE --cap-add FOWNER --cap-add FSETID --cap-add SETUID --cap-add SETGID --cap-add KILL --cap-add AUDIT_WRITE --cap-add NET_BIND_SERVICE"
# shellcheck disable=SC2086
ok "sudo fonctionne avec les capacités du mode par défaut" out_has root in_image $CAPS "$IMG" sudo id -un
no "sudo refusé avec --no-sudo" in_image --cap-drop ALL --security-opt no-new-privileges "$IMG" sudo true
ok "mise et jq présents" in_image "$IMG" sh -c 'mise --version && jq --version'

MANAGED="-v $ROOT/config/managed:/etc/claude-code:ro"
# shellcheck disable=SC2086
no "/etc/claude-code non modifiable, même avec sudo" in_image $CAPS $MANAGED "$IMG" sudo touch /etc/claude-code/x
# shellcheck disable=SC2086
ok "managed-settings.json valide" in_image $MANAGED "$IMG" jq -e '.hooks.PreToolUse and .hooks.SessionStart' /etc/claude-code/managed-settings.json
# shellcheck disable=SC2086
ok "hook de push dans le conteneur" in_image $MANAGED -v "$ROOT/tests:/tests:ro" -e HOOK=/etc/claude-code/hooks/push-guard.sh "$IMG" bash /tests/push-guard.test.sh
# shellcheck disable=SC2086
ok "synchro des agents dans le conteneur" in_image $MANAGED -v "$ROOT/tests:/tests:ro" -e SYNC=/etc/claude-code/agents-sync.sh "$IMG" bash /tests/agents-sync.test.sh

mkdir -p "$TMP/proj/.claude-docker"
printf '# outils du projet\nfile\ntree  # arborescence\n' > "$TMP/proj/.claude-docker/packages"
ok "paquets du projet : image dérivée construite" out_has "installation des paquets" launch --version
no "paquets du projet : pas de réinstallation ensuite" out_has "installation des paquets" launch --version
pkg_image="$(docker images --format '{{.Repository}}:{{.Tag}}' | grep "^$IMG-pkg:" | head -n 1)"
ok "paquets du projet : installés, utilisateur dev" in_image "$pkg_image" sh -c 'tree --version && file --version && [ "$(id -un)" = dev ]'
ok "--clean supprime les images de paquets" out_has "1 image(s) de paquets supprimée(s)" launch --clean
no "--clean : plus d'image dérivée" docker image inspect "$pkg_image"
ok "--clean sans rien à supprimer" out_has "0 image(s)" launch --clean
echo 'tree; rm -rf /' > "$TMP/proj/.claude-docker/packages"
ok "nom de paquet invalide refusé" out_has "nom de paquet invalide" launch --version

if [ "$fail" -gt 0 ]; then
    echo "docker : $fail échec(s) sur $n"
    exit 1
fi
echo "docker : $n vérifications OK"
