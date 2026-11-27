#!/usr/bin/env bash
# Hook PreToolUse (Bash) : tout ce qui publie sur un remote (git push, merge de
# PR) demande l'accord de l'utilisateur, sauf :
#   - les repos d'agents de CLAUDE_AGENTS_PUSH ;
#   - les couples repo:branche de CLAUDE_PUSH_ALLOW (ex. api:claude/*).
# Dans le doute (chemin non résolu, --force, refspec inhabituel), il demande.
set -u

input="$(cat)"
case "$input" in *push*|*merge*) ;; *) exit 0 ;; esac

if ! command -v jq >/dev/null 2>&1; then
    echo "push-guard: jq absent de l'image, relance avec claude-docker --rebuild" >&2
    exit 2
fi

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
[ -n "$cwd" ] || cwd="$PWD"

ask() {
    jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse",
        permissionDecision: "ask", permissionDecisionReason: $r}}'
    exit 0
}

# Chemin absolu réel d'un dossier, vide s'il n'existe pas
real() { (cd "$1" 2>/dev/null && pwd -P); }

# $1 relatif à $2 ; vide si le chemin contient une variable non développée
resolve() {
    local p=$1
    # shellcheck disable=SC2088
    case "$p" in
        *'$'*|*'`'*) return ;;
        '~') p=$HOME ;;
        '~/'*) p="$HOME/${p#\~/}" ;;
    esac
    case "$p" in /*) ;; *) p="$2/$p" ;; esac
    real "$p"
}

in_list() { case ",$2," in *",$1,"*) return 0 ;; esac; return 1; }

# Le dépôt $1 est-il un repo d'agents inscriptible ?
is_push_hub() {
    local top=$1 entry name src hub
    local IFS=,
    for entry in ${CLAUDE_AGENTS_REPOS:-}; do
        name=${entry%%=*}; src=${entry#*=}
        in_list "$name" "${CLAUDE_AGENTS_PUSH:-}" || continue
        case "$src" in
            /*) hub=$src ;;
            *)  hub="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/agents-repos/$name" ;;
        esac
        [ "$(real "$hub")" = "$top" ] && return 0
    done
    return 1
}

# La branche $2 du repo nommé $1 est-elle dans CLAUDE_PUSH_ALLOW ?
branch_allowed() {
    local repo=$1 branch=$2 entry glob
    local IFS=,
    for entry in ${CLAUDE_PUSH_ALLOW:-}; do
        [ "${entry%%:*}" = "$repo" ] || continue
        glob=${entry#*:}
        # shellcheck disable=SC2254
        case "$branch" in $glob) return 0 ;; esac
    done
    return 1
}

# Analyse « git push <args> » lancé depuis $dir. Retourne 0 si autorisé.
push_allowed() {
    local dir=$1; shift
    local a remote="" refs="" skip=0 top url repo branch
    for a in "$@"; do
        if [ "$skip" = 1 ]; then skip=0; continue; fi
        case "$a" in
            --force*|--delete|--mirror|--all|--tags|--follow-tags|--prune|--repo*|--receive-pack*|--exec*)
                return 1 ;;
            -o|--push-option) skip=1 ;;
            --*) ;;
            -*) case "$a" in *f*|*d*) return 1 ;; esac ;;
            *:*|+*) return 1 ;;
            *) if [ -z "$remote" ]; then remote=$a; else refs="$refs $a"; fi ;;
        esac
    done

    [ -n "$dir" ] || return 1
    top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || return 1
    top="$(real "$top")"
    # Le remote doit être un remote configuré du repo, pas une URL
    url="$(git -C "$top" remote get-url "${remote:-origin}" 2>/dev/null)" || return 1

    is_push_hub "$top" && return 0

    repo=${url%/}; repo=${repo%.git}; repo=${repo##*/}; repo=${repo##*:}
    if [ -z "$refs" ]; then
        refs="$(git -C "$top" symbolic-ref --short -q HEAD)" || return 1
    fi
    for branch in $refs; do
        if [ "$branch" = HEAD ]; then
            branch="$(git -C "$top" symbolic-ref --short -q HEAD)" || return 1
        fi
        branch_allowed "$repo" "$branch" || return 1
    done
    return 0
}

# Découpe la commande en commandes simples
segments="$(printf '%s\n' "$cmd" | sed -e 's/&&/;/g' -e 's/||/;/g' -e 's/\$(/;/g' | tr ';|()`&' '\n')"

dir="$(real "$cwd")"
while IFS= read -r seg; do
    set -f
    # shellcheck disable=SC2086
    set -- $seg
    set +f
    [ $# -gt 0 ] || continue

    if [ "$1" = cd ] && [ $# -ge 2 ]; then
        t=${2//\"/}; t=${t//\'/}
        dir="$(resolve "$t" "$dir")"
        continue
    fi

    while [ $# -gt 0 ]; do
        tok=${1//\"/}; tok=${tok//\'/}
        shift
        case "$tok" in
            gh|*/gh)
                if [ "${1:-}" = pr ] && [ "${2:-}" = merge ]; then
                    ask "Merge de PR : accord de l'utilisateur requis."
                fi
                break ;;
            git|*/git) ;;
            *) continue ;;
        esac

        # Options globales de git, jusqu'à la sous-commande
        gdir=$dir
        while [ $# -gt 0 ]; do
            tok=${1//\"/}; tok=${tok//\'/}
            case "$tok" in
                -C) t=${2:-}; t=${t//\"/}; t=${t//\'/}
                    gdir="$(resolve "$t" "$gdir")"; shift 2 2>/dev/null || shift ;;
                -c|--git-dir|--work-tree|--namespace) shift 2 2>/dev/null || shift ;;
                --git-dir=*|--work-tree=*) gdir=""; shift ;;
                -*) shift ;;
                *) break ;;
            esac
        done
        if [ "${1:-}" = push ]; then
            shift
            args=()
            for t in "$@"; do t=${t//\"/}; t=${t//\'/}; args+=("$t"); done
            push_allowed "$gdir" ${args[@]+"${args[@]}"} ||
                ask "git push hors des cas autorisés (CLAUDE_AGENTS_PUSH, CLAUDE_PUSH_ALLOW) : accord de l'utilisateur requis."
        fi
        break
    done
done <<EOF
$segments
EOF

exit 0
