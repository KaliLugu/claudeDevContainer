# shellcheck shell=bash
# Règle de push partagée par le hook push-guard.sh et par l'enveloppe de git
# (config/managed/bin/git). À sourcer.
#
# Un push passe sans accord de l'utilisateur seulement pour :
#   - les repos d'agents de CLAUDE_AGENTS_PUSH ;
#   - les couples repo:branche de CLAUDE_PUSH_ALLOW (ex. api:claude/*).

# Le vrai git : l'enveloppe le fixe pour ne pas se rappeler elle-même
PUSH_GIT="${PUSH_GIT:-git}"

# Témoin posé par le hook quand il demande l'accord de l'utilisateur : tant
# qu'il existe, l'enveloppe de git laisse passer les push de la commande en
# cours. Le hook l'efface au début de chaque commande suivante.
PUSH_MARK_DIR="${TMPDIR:-/tmp}/claude-push-guard-$(id -u)"
push_mark_set() { mkdir -p "$PUSH_MARK_DIR" && chmod 700 "$PUSH_MARK_DIR" && : > "$PUSH_MARK_DIR/ask"; }
push_mark_clear() { rm -rf "$PUSH_MARK_DIR"; }
push_mark_present() { [ -e "$PUSH_MARK_DIR/ask" ]; }

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
    top="$("$PUSH_GIT" -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || return 1
    top="$(real "$top")"
    # Le remote doit être un remote configuré du repo, pas une URL
    url="$("$PUSH_GIT" -C "$top" remote get-url "${remote:-origin}" 2>/dev/null)" || return 1

    is_push_hub "$top" && return 0

    repo=${url%/}; repo=${repo%.git}; repo=${repo##*/}; repo=${repo##*:}
    if [ -z "$refs" ]; then
        refs="$("$PUSH_GIT" -C "$top" symbolic-ref --short -q HEAD)" || return 1
    fi
    for branch in $refs; do
        if [ "$branch" = HEAD ]; then
            branch="$("$PUSH_GIT" -C "$top" symbolic-ref --short -q HEAD)" || return 1
        fi
        branch_allowed "$repo" "$branch" || return 1
    done
    return 0
}
