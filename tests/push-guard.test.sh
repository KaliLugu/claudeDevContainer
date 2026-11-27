#!/usr/bin/env bash
# Tests du hook push-guard : chaque cas donne une commande Bash et la décision
# attendue (ask = accord demandé, pass = laissé passer).
# Usage : tests/push-guard.test.sh        (nécessite git et jq)
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="${HOOK:-$ROOT/config/managed/hooks/push-guard.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
unset CLAUDE_CONFIG_DIR
mkdir -p "$HOME/.claude/agents-repos"

mkrepo() { # <dossier> <url origin> <branche>
    git init -q -b "$3" "$1"
    git -C "$1" remote add origin "$2"
}
mkrepo "$TMP/api" git@github.com:acme/api.git claude/fix
mkrepo "$TMP/front" https://github.com/acme/front.git main
mkrepo "$TMP/hub-local" git@github.com:me/agents.git main
mkrepo "$HOME/.claude/agents-repos/equipe" git@github.com:acme/agents.git main
mkrepo "$HOME/.claude/agents-repos/lecture" git@github.com:other/agents.git main

export CLAUDE_AGENTS_REPOS="perso=$TMP/hub-local,equipe=git@github.com:acme/agents.git,lecture=git@github.com:other/agents.git"
export CLAUDE_AGENTS_PUSH="perso,equipe"
export CLAUDE_PUSH_ALLOW="api:claude/*,front:release"

fail=0
n=0
check() { # <attendu> <cwd> <commande>
    local want=$1 cwd=$2 cmd=$3 out got
    out="$(jq -n --arg c "$cmd" --arg d "$cwd" '{tool_name: "Bash", cwd: $d, tool_input: {command: $c}}' | bash "$HOOK")"
    case "$out" in *'"ask"'*) got=ask ;; "") got=pass ;; *) got="?($out)" ;; esac
    n=$((n + 1))
    if [ "$got" != "$want" ]; then
        fail=$((fail + 1))
        echo "ÉCHEC  attendu=$want obtenu=$got  [$cwd] $cmd"
    fi
}

# Sans rapport avec un push
check pass "$TMP/api" "ls -la"
check pass "$TMP/api" "git status && git log --oneline -3"
check pass "$TMP/api" "git stash push -m wip"
check pass "$TMP/api" "git commit -m 'prépare le push'"
check pass "$TMP/api" "git pull --rebase && git fetch origin"
check pass "$TMP/api" "gh pr view 12"

# Push non autorisés
check ask "$TMP/front" "git push"
check ask "$TMP/front" "git push origin main"
check ask "$TMP" "git -C front push"
check ask "$TMP" "cd front && git push"
check ask "$TMP/api" "git add -A; git commit -m x; git push origin main"
check ask "$TMP/api" "git push --force"
check ask "$TMP/api" "git push -f origin claude/fix"
check ask "$TMP/api" "git push origin claude/fix:main"
check ask "$TMP/api" "git push origin --delete claude/fix"
check ask "$TMP/api" "git push --tags"
check ask "$TMP/api" "git push https://example.com/x.git claude/fix"
check ask "$TMP/api" "git push autre claude/fix"
check ask "$TMP/api" 'git -C "$REPO" push'
check ask "$TMP/api" "/usr/bin/git push origin main"
check ask "$TMP/api" "FOO=1 git -c user.name=x push origin main"
check ask "$TMP/api" 'echo $(git push origin main)'
check ask "$TMP" "git push"
check ask "$TMP/api" "gh pr merge 12 --squash"

# Push autorisés par CLAUDE_PUSH_ALLOW
check pass "$TMP/api" "git push"
check pass "$TMP/api" "git push origin claude/fix"
check pass "$TMP/api" "git push -u origin claude/fix"
check pass "$TMP/api" "git push origin HEAD"
check pass "$TMP" "git -C api push origin claude/autre"
check pass "$TMP" "cd api && git push"
check pass "$TMP/front" "git push origin release"

# Repos d'agents
check pass "$TMP" "git -C $TMP/hub-local push"
check pass "$TMP/hub-local" "git add a.md && git commit -m x && git pull --rebase && git push"
check pass "$TMP" "git -C ~/.claude/agents-repos/equipe push"
check ask "$TMP" "git -C ~/.claude/agents-repos/lecture push"
check ask "$TMP" "git -C $TMP/hub-local push --force"

if [ "$fail" -gt 0 ]; then
    echo "push-guard : $fail échec(s) sur $n"
    exit 1
fi
echo "push-guard : $n cas OK"
