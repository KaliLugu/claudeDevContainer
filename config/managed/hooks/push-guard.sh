#!/usr/bin/env bash
# Hook PreToolUse (Bash) : tout ce qui publie sur un remote (git push, merge de
# PR) demande l'accord de l'utilisateur, sauf les cas de push-policy.sh.
# Dans le doute (chemin non résolu, --force, refspec inhabituel), il demande.
set -u

# shellcheck source=config/managed/hooks/push-policy.sh
. "$(dirname "$0")/push-policy.sh"

# Un accord ne vaut que pour la commande qui l'a obtenu
push_mark_clear

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
            if ! push_allowed "$gdir" ${args[@]+"${args[@]}"}; then
                push_mark_set
                ask "git push hors des cas autorisés (CLAUDE_AGENTS_PUSH, CLAUDE_PUSH_ALLOW) : accord de l'utilisateur requis."
            fi
        fi
        break
    done
done <<EOF
$segments
EOF

exit 0
