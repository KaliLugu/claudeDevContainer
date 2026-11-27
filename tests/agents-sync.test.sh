#!/usr/bin/env bash
# Tests de agents-sync.sh, avec des repos git locaux à la place d'une forge.
# Usage : tests/agents-sync.test.sh       (nécessite git)
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SYNC="${SYNC:-$ROOT/config/managed/agents-sync.sh}"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_SYSTEM=/dev/null
unset CLAUDE_CONFIG_DIR CLAUDE_AGENTS_PUSH
mkdir -p "$HOME"
git config --global user.name test
git config --global user.email test@example.com
git config --global init.defaultBranch main
git config --global protocol.file.allow always

# Dans le conteneur, git refuse les push : la préparation des dépôts de test
# passe par le vrai git.
REAL_GIT=git
[ -x /usr/lib/git-core/git ] && REAL_GIT=/usr/lib/git-core/git

fail=0
n=0
ok() { # <description> <commande...>
    local what=$1; shift
    n=$((n + 1))
    if ! "$@" >/dev/null 2>&1; then
        fail=$((fail + 1))
        echo "ÉCHEC  $what"
    fi
}
no() { local what=$1; shift; ok "$what" not "$@"; }
not() { ! "$@"; }
contains() { grep -qF -- "$2" "$1"; }

commit_file() { # <repo> <fichier> <contenu>
    mkdir -p "$(dirname "$1/$2")"
    printf '%s\n' "$3" > "$1/$2"
    git -C "$1" add "$2" && git -C "$1" commit -q -m "$2"
}

# Une « forge » : repo d'agents d'équipe, avec deux projets
git init -q "$TMP/forge-src"
commit_file "$TMP/forge-src" plateforme/CLAUDE.md "Carte de la plateforme"
commit_file "$TMP/forge-src" plateforme/agents/api.md "agent api (équipe)"
commit_file "$TMP/forge-src" autre/agents/front.md "agent front (autre projet)"
commit_file "$TMP/forge-src" autre/agents/inutile.md "agent non lié"
git clone -q --bare "$TMP/forge-src" "$TMP/forge.git"
git -C "$TMP/forge-src" remote add origin "$TMP/forge.git"

# Un repo d'agents perso : copie de travail locale, prioritaire
git init -q "$TMP/perso-src"
commit_file "$TMP/perso-src" plateforme/agents/infra.md "agent infra (perso)"
git clone -q --bare "$TMP/perso-src" "$TMP/perso.git"
git clone -q "$TMP/perso.git" "$TMP/perso"

# Le projet lancé : multirepo api + front + infra + sans-agent
P="$TMP/plateforme"
for r in api front infra sans-agent; do
    git init -q "$P/$r"
    git -C "$P/$r" remote add origin "git@example.com:acme/$r.git"
done
mkdir -p "$P/pas-un-repo"

export CLAUDE_AGENTS_REPOS="perso=$TMP/perso,equipe=file://$TMP/forge.git,casse=file://$TMP/absent.git"
A="$HOME/.claude/agents"
CTX="$HOME/.claude/agents-repos/session-context.md"
run() { (cd "$P" && bash "$SYNC"); }

# --- Premier lancement
ok "le script se termine sans erreur" run
ok "clone du repo equipe" test -d "$HOME/.claude/agents-repos/equipe/.git"
ok "agent api lié (projet du même nom)" contains "$A/api.md" "agent api (équipe)"
ok "agent front lié (autre projet)" contains "$A/front.md" "agent front"
ok "agent infra lié (copie locale)" contains "$A/infra.md" "agent infra (perso)"
no "pas de lien pour un repo sans agent" test -e "$A/sans-agent.md"
no "les agents non demandés ne sont pas liés" test -e "$A/inutile.md"
ok "contexte du projet transmis" contains "$CTX" "Carte de la plateforme"
ok "agents récupérés signalés" contains "$CTX" 'Agent `api` récupéré'
ok "repo injoignable signalé" contains "$CTX" '`casse` injoignable'
no "repo injoignable non cloné" test -d "$HOME/.claude/agents-repos/casse"

# --- Deuxième lancement : rien de nouveau
ok "deuxième lancement" run
no "rien à signaler pour les agents déjà liés" contains "$CTX" "récupéré"
ok "le contexte est toujours transmis" contains "$CTX" "Carte de la plateforme"

# --- Mise à jour côté forge, vérification récente : pas de fetch
commit_file "$TMP/forge-src" plateforme/agents/api.md "agent api v2"
"$REAL_GIT" -C "$TMP/forge-src" push -q origin main
ok "lancement dans le délai" run
ok "pas de mise à jour avant le délai" contains "$A/api.md" "agent api (équipe)"

# --- Délai dépassé : mise à jour récupérée et résumée
export CLAUDE_AGENTS_CHECK_HOURS=0
ok "lancement après le délai" run
ok "mise à jour récupérée" contains "$A/api.md" "agent api v2"
ok "mise à jour résumée" contains "$CTX" '`equipe` mis à jour'

# --- Copie locale avec modifications en cours : jamais touchée
git clone -q "$TMP/perso.git" "$TMP/perso-autre"
commit_file "$TMP/perso-autre" plateforme/agents/infra.md "agent infra v2"
"$REAL_GIT" -C "$TMP/perso-autre" push -q origin main
echo "brouillon" > "$TMP/perso/brouillon.md"
ok "lancement avec copie locale modifiée" run
ok "copie locale non avancée" contains "$TMP/perso/plateforme/agents/infra.md" "agent infra (perso)"
ok "brouillon conservé" contains "$TMP/perso/brouillon.md" "brouillon"
ok "retard signalé" contains "$CTX" "modifications en cours"
rm "$TMP/perso/brouillon.md"
ok "lancement avec copie locale propre" run
ok "copie locale avancée" contains "$TMP/perso/plateforme/agents/infra.md" "agent infra v2"

# --- Un agent local au projet a priorité, un lien cassé est réparé
rm "$A/front.md" && mkdir -p "$P/.claude/agents" && echo local > "$P/.claude/agents/front.md"
ln -sfn "$TMP/nulle-part.md" "$A/api.md"
ok "lancement avec agent local et lien cassé" run
no "agent local : pas de lien" test -e "$A/front.md"
ok "lien cassé réparé" contains "$A/api.md" "agent api v2"

# --- Mono-repo, et absence de CLAUDE_AGENTS_REPOS
rm -f "$A"/*.md
ok "lancement en mono-repo" sh -c "cd '$P/api' && bash '$SYNC'"
ok "mono-repo : agent lié depuis un autre projet" contains "$A/api.md" "agent api v2"
unset CLAUDE_AGENTS_REPOS
rm -f "$CTX"
ok "sans repos d'agents : ne fait rien" run
no "sans repos d'agents : pas de contexte" test -e "$CTX"

if [ "$fail" -gt 0 ]; then
    echo "agents-sync : $fail échec(s) sur $n"
    [ -f "$CTX" ] && { echo "--- dernier contexte :"; cat "$CTX"; }
    exit 1
fi
echo "agents-sync : $n vérifications OK"
