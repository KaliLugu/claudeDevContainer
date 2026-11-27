#!/usr/bin/env bash
# Synchronise les repos d'agents (CLAUDE_AGENTS_REPOS) avant le démarrage de
# Claude, depuis le dossier de lancement :
#   1. clone les repos donnés par URL, récupère les mises à jour si la dernière
#      vérification date de plus de CLAUDE_AGENTS_CHECK_HOURS heures ;
#   2. lie dans ~/.claude/agents/ les agents des repos du projet qui n'en ont pas ;
#   3. écrit ce que Claude doit savoir dans agents-repos/session-context.md,
#      injecté dans la session par un hook SessionStart.
# Ne modifie jamais une copie de travail locale qui a des changements en cours.
set -u

[ -n "${CLAUDE_AGENTS_REPOS:-}" ] || exit 0

CONF="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STORE="$CONF/agents-repos"
AGENTS="$CONF/agents"
STATE="$STORE/state.tsv"
CONTEXT="$STORE/session-context.md"
LAUNCH="$(pwd -P)"
PROJECT="$(basename "$LAUNCH")"
MAX_AGE=$(( ${CLAUDE_AGENTS_CHECK_HOURS:-24} * 3600 ))
NOW="$(date +%s)"

mkdir -p "$STORE" "$AGENTS"
touch "$STATE"
rm -f "$CONTEXT"

export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=10}"

notes=""
note() { notes="$notes- $*"$'\n'; }

# Limite la durée des commandes réseau quand timeout(1) est disponible
net() { if command -v timeout >/dev/null 2>&1; then timeout 60 "$@"; else "$@"; fi; }

last_check() { awk -F'\t' -v n="$1" '$1 == n { print $2 }' "$STATE" | tail -n 1; }
record_check() {
    local tmp="$STATE.tmp"
    awk -F'\t' -v n="$1" '$1 != n' "$STATE" > "$tmp"
    printf '%s\t%s\n' "$1" "$NOW" >> "$tmp"
    mv "$tmp" "$STATE"
}

has_head() { git -C "$1" rev-parse -q --verify HEAD >/dev/null 2>&1; }

# Rend le dossier <projet> présent dans un clone partiel
checkout_project() { # <hub> <clone|local> <projet>
    [ "$2" = clone ] || return 0
    git -C "$1" sparse-checkout add "$3" >/dev/null 2>&1
}

# --- 1. Repos d'agents : clone et mises à jour ------------------------------

names=()
hubs=()
kinds=()

update_hub() { # <nom> <hub> <clone|local>
    local name=$1 hub=$2 kind=$3 last new log
    last="$(last_check "$name")"
    case "$last" in ''|*[!0-9]*) last=0 ;; esac
    [ $(( NOW - last )) -ge "$MAX_AGE" ] || return 0

    # Sans branche suivie (repo sans remote, ou vide) : rien à récupérer
    if ! git -C "$hub" rev-parse -q --verify '@{u}' >/dev/null 2>&1; then
        record_check "$name"
        return 0
    fi
    if ! net git -C "$hub" fetch --quiet 2>/dev/null; then
        note "Repo d'agents \`$name\` injoignable : mises à jour non vérifiées."
        return 0
    fi
    new="$(git -C "$hub" rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)"
    if [ "$new" -gt 0 ]; then
        log="$(git -C "$hub" log --oneline -n 5 'HEAD..@{u}' -- "$PROJECT" 2>/dev/null)"
        if [ "$kind" = local ] && [ -n "$(git -C "$hub" status --porcelain 2>/dev/null)" ]; then
            note "Repo d'agents \`$name\` : copie locale en retard de $new commit(s), non mise à jour car elle a des modifications en cours."
        elif [ "$kind" = local ] && ! git -C "$hub" pull --ff-only --quiet 2>/dev/null; then
            note "Repo d'agents \`$name\` : copie locale en retard de $new commit(s), branches divergentes, non mise à jour."
        elif [ "$kind" = clone ] && ! git -C "$hub" pull --rebase --quiet 2>/dev/null; then
            git -C "$hub" rebase --abort >/dev/null 2>&1
            note "Repo d'agents \`$name\` : $new commit(s) à récupérer, mais le rebase a échoué (conflit avec des commits locaux)."
        elif [ -n "$log" ]; then
            note "Repo d'agents \`$name\` mis à jour, pour le projet \`$PROJECT\` :"$'\n'"$(printf '%s\n' "$log" | sed 's/^/    /')"
        fi
    fi
    record_check "$name"
}

IFS=, read -ra entries <<< "$CLAUDE_AGENTS_REPOS"
for entry in ${entries[@]+"${entries[@]}"}; do
    name=${entry%%=*}
    src=${entry#*=}
    [ -n "$name" ] && [ -n "$src" ] && [ "$name" != "$entry" ] || continue
    case "$src" in
        /*)
            hub=$src; kind=local
            if ! git -C "$hub" rev-parse --git-dir >/dev/null 2>&1; then
                note "Repo d'agents \`$name\` : \`$hub\` n'est pas un repo git (ignoré)."
                continue
            fi ;;
        *)
            hub="$STORE/$name"; kind=clone
            if [ ! -d "$hub/.git" ]; then
                if ! net git clone --quiet --filter=blob:none --sparse "$src" "$hub" 2>/dev/null; then
                    rm -rf "$hub"
                    note "Repo d'agents \`$name\` injoignable : clone impossible."
                    continue
                fi
                record_check "$name"
            fi ;;
    esac
    names+=("$name"); hubs+=("$hub"); kinds+=("$kind")
    update_hub "$name" "$hub" "$kind"
done

count=${#names[@]}
if [ "$count" -eq 0 ]; then
    [ -z "$notes" ] || printf '# Repos d'"'"'agents : à signaler à l'"'"'utilisateur\n\n%s' "$notes" > "$CONTEXT"
    exit 0
fi

# --- 2. Agents manquants pour les repos du projet lancé ---------------------

repo_name() { # <dossier du repo>
    local url
    url="$(git -C "$1" remote get-url origin 2>/dev/null)" || url=""
    if [ -n "$url" ]; then
        url=${url%/}; url=${url%.git}; url=${url##*/}; url=${url##*:}
        printf '%s\n' "$url"
    else
        basename "$1"
    fi
}

# Cherche <repo>.md dans les repos d'agents : d'abord dans le projet du même
# nom que le dossier de lancement, puis dans n'importe quel projet.
# Affiche « <indice du hub> <projet> ».
find_agent() { # <repo>
    local repo=$1 i match
    for (( i = 0; i < count; i++ )); do
        has_head "${hubs[$i]}" || continue
        if git -C "${hubs[$i]}" cat-file -e "HEAD:$PROJECT/agents/$repo.md" 2>/dev/null; then
            echo "$i $PROJECT"; return 0
        fi
    done
    for (( i = 0; i < count; i++ )); do
        has_head "${hubs[$i]}" || continue
        match="$(git -C "${hubs[$i]}" ls-tree -r --name-only HEAD |
            awk -F/ -v f="$repo.md" 'NF == 3 && $2 == "agents" && $3 == f { print $1; exit }')"
        if [ -n "$match" ]; then echo "$i $match"; return 0; fi
    done
    return 1
}

repos=()
if [ "$(git -C "$LAUNCH" rev-parse --show-toplevel 2>/dev/null)" = "$LAUNCH" ]; then
    repos+=("$LAUNCH")
else
    for d in "$LAUNCH"/*/; do
        [ -e "${d}.git" ] && repos+=("${d%/}")
    done
fi

for dir in ${repos[@]+"${repos[@]}"}; do
    repo="$(repo_name "$dir")"
    link="$AGENTS/$repo.md"
    [ -e "$link" ] && continue
    [ -f "$LAUNCH/.claude/agents/$repo.md" ] && continue
    found="$(find_agent "$repo")" || continue
    i=${found%% *}; project=${found#* }
    checkout_project "${hubs[$i]}" "${kinds[$i]}" "$project"
    target="${hubs[$i]}/$project/agents/$repo.md"
    [ -f "$target" ] || continue
    # $link n'existe pas ici, ou c'est un lien cassé : on le remplace
    ln -sfn "$target" "$link"
    note "Agent \`$repo\` récupéré depuis le repo d'agents \`${names[$i]}\` (projet \`$project\`)."
done

# --- 3. Contexte du projet lancé ---------------------------------------------

context=""
for (( i = 0; i < count; i++ )); do
    has_head "${hubs[$i]}" || continue
    git -C "${hubs[$i]}" cat-file -e "HEAD:$PROJECT/CLAUDE.md" 2>/dev/null || continue
    checkout_project "${hubs[$i]}" "${kinds[$i]}" "$PROJECT"
    file="${hubs[$i]}/$PROJECT/CLAUDE.md"
    [ -f "$file" ] || continue
    context="# Contexte du projet \`$PROJECT\` (\`$file\`)"$'\n\n'"$(cat "$file")"$'\n'
    break
done

{
    if [ -n "$notes" ]; then
        printf '# Repos d'"'"'agents : à signaler à l'"'"'utilisateur, en une ou deux lignes\n\n%s\n' "$notes"
    fi
    [ -z "$context" ] || printf '%s' "$context"
} > "$CONTEXT"
[ -s "$CONTEXT" ] || rm -f "$CONTEXT"
exit 0
