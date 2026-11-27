#!/usr/bin/env bash
# Tests de l'enveloppe de git (config/managed/bin/git), à lancer DANS le
# conteneur, où elle est montée en /usr/local/bin/git devant le vrai git :
# tests/docker.test.sh s'en charge.
set -u

if [ "$(command -v git)" != /usr/local/bin/git ] || [ ! -f /etc/claude-code/hooks/push-policy.sh ]; then
    echo "git-wrapper : à lancer dans le conteneur (voir tests/docker.test.sh)"
    exit 1
fi

HOOK=/etc/claude-code/hooks/push-guard.sh
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_SYSTEM=/dev/null
unset CLAUDE_CONFIG_DIR CLAUDE_AGENTS_REPOS CLAUDE_AGENTS_PUSH CLAUDE_PUSH_ALLOW
mkdir -p "$HOME"
git config --global user.name test
git config --global user.email test@example.com
git config --global init.defaultBranch main

fail=0
n=0
ok() { # <description> <commande...>
    local what=$1; shift
    n=$((n + 1))
    if ! "$@" >"$TMP/out" 2>&1; then
        fail=$((fail + 1))
        echo "ÉCHEC  $what"
        tail -n 8 "$TMP/out" | sed 's/^/    /'
    fi
}
no() { local what=$1; shift; ok "$what" not "$@"; }
not() { ! "$@"; }

# Un repo « api » avec un remote local, pour que les push autorisés aboutissent
git init -q --bare "$TMP/api.git"
git clone -q "$TMP/api.git" "$TMP/api" 2>/dev/null
cd "$TMP/api" || exit 1
git checkout -q -b main
echo a > a.txt && git add a.txt && git commit -q -m a
remote_has() { /usr/bin/git -C "$TMP/api.git" rev-parse -q --verify "refs/heads/$1" >/dev/null; }
hook() { # <commande Bash>
    jq -n --arg c "$1" --arg d "$PWD" '{tool_name: "Bash", cwd: $d, tool_input: {command: $c}}' | bash "$HOOK"
}

# Ce qui n'est pas un push n'est pas touché
ok "git status passe" git status
ok "git log passe" git log --oneline
echo b > b.txt
ok "git stash push passe" git stash push -u -m essai
ok "git stash pop passe" git stash pop
ok "git commit -m 'push' passe" git commit -q --allow-empty -m "avant le push"

# Push sans accord ni exception : refusé, rien n'arrive sur le remote
no "git push refusé" git push origin main
ok "message d'explication" sh -c 'git push origin main 2>&1 | grep -q "push refusé"'
no "rien sur le remote" remote_has main
no "push refusé depuis un script" bash -c 'git push origin main'
no "push refusé avec -C" git -C "$TMP/api" push origin main
no "push refusé avec -c" git -c user.name=x push origin main

# Accord demandé par le hook : le push de cette commande passe
ok "le hook demande l'accord" sh -c "$(declare -f hook); HOOK=$HOOK; hook 'git push origin main' | grep -q '\"ask\"'"
ok "push accepté après la demande d'accord" git push origin main
ok "le push est arrivé sur le remote" remote_has main

# L'accord ne vaut pas pour la commande suivante
hook "ls" >/dev/null
git checkout -q -b autre
no "push refusé à la commande suivante" git push origin autre
no "rien de plus sur le remote" remote_has autre

# Exception CLAUDE_PUSH_ALLOW : passe sans accord, dans son périmètre seulement
export CLAUDE_PUSH_ALLOW="api:claude/*"
git checkout -q -b claude/essai
ok "push d'une branche autorisée" git push -u origin claude/essai
ok "branche autorisée arrivée sur le remote" remote_has claude/essai
no "push --force refusé malgré l'exception" git push --force origin claude/essai
no "autre branche toujours refusée" git push origin autre
no "refspec vers une autre branche refusé" git push origin claude/essai:main

if [ "$fail" -gt 0 ]; then
    echo "git-wrapper : $fail échec(s) sur $n"
    exit 1
fi
echo "git-wrapper : $n vérifications OK"
