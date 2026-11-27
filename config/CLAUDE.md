# Règles globales (conteneur claude-docker)

## Mémoire de repo pour agents spécialisés

Claude tient, pour chaque repo, un fichier d'agent décrivant ce qu'il faut
savoir pour y travailler, et pour chaque projet un fichier de contexte. Deux
modes, selon la variable d'environnement `CLAUDE_AGENTS_REPOS` :

- **Définie** → mode **repos d'agents** : tout vit dans des repos séparés
  (voir « Repos d'agents » plus bas).
- **Absente** → mode **local** : les règles ne s'appliquent que si le dossier
  de lancement contient `.claude/agents/` (opt-in), ou si l'utilisateur le
  demande. Sinon, ne crée aucun de ces fichiers.

### Projet et fichiers

Un **projet** est ce sur quoi on lance claude-docker : un repo seul
(mono-repo) ou un dossier parent regroupant plusieurs repos (multirepo). Son
nom est le nom du dossier de lancement, sauf indication de l'utilisateur.

| Fichier | Mode local | Mode repos d'agents |
|---|---|---|
| Agent d'un repo | `<lancement>/.claude/agents/<repo>.md` | `<hub>/<projet>/agents/<repo>.md` |
| Contexte du projet | `<lancement>/CLAUDE.md` (multirepo seulement) | `<hub>/<projet>/CLAUDE.md` |

(`<hub>` = le clone d'un des repos d'agents, voir plus bas.)

Le contexte du projet liste les repos (chemin, rôle en une ligne, agent
associé) et leurs liens (qui appelle qui, contrats partagés, ordre de
déploiement). En mono-repo il reste court.

### Format d'un fichier d'agent

Ce sont des subagents Claude Code, donc ce format exact :

```markdown
---
name: <nom-du-repo>
description: Expert du repo <nom-du-repo> (<chemin relatif au dossier de lancement>). À utiliser pour <cas d'usage concrets>.
---

Tu es spécialiste du repo `<chemin relatif>`. Travaille dans ce dossier.

## Rôle
## Stack et commandes (build, test, lint, lancement)
## Architecture (dossiers clés, points d'entrée)
## Conventions (style, nommage, branches, commits)
## Interfaces avec les autres repos (API, schémas, events, libs partagées)
## Pièges connus
```

Le `name` doit être unique parmi les agents liés : en cas de collision
(deux projets ou deux repos d'agents), préfixe-le par le projet
(`<projet>-<repo>`), ainsi que le nom du fichier.

### Quand l'écrire ou le mettre à jour

- Au premier travail significatif sur un repo qui n'a pas encore d'agent.
- Quand tu découvres quelque chose de non évident et durable : une commande
  qui ne marche que d'une certaine façon, un couplage entre repos, une
  convention implicite, un piège qui t'a coûté du temps.
- N'y mets pas ce qui se lit directement dans le code ou l'historique git,
  ni de détails propres à la tâche en cours, ni de secrets.
- Modifie la section concernée plutôt que d'empiler ; supprime ce qui est
  devenu faux. Garde chaque fichier court (idéalement < 150 lignes).
- Signale à l'utilisateur, en une ligne, chaque fichier créé ou modifié.

### Utilisation

Pour une tâche qui touche un repo précis, délègue à son agent quand c'est
utile ; pour une tâche transverse, appuie-toi sur le contexte du projet et
coordonne les agents des repos concernés.

## Repos d'agents

Ne s'applique que si `CLAUDE_AGENTS_REPOS` est définie : liste `nom=source`
séparés par des virgules, par ordre de priorité. La source est :

- une **URL git** → cloné dans `~/.claude/agents-repos/<nom>` (persistant),
  en **clone partiel** : seuls les projets utilisés sont téléchargés ;
- un **chemin absolu** → copie de travail de l'utilisateur, montée par
  claude-docker : utilise-la telle quelle (pas de clone, pas de sparse).

Dans la suite, `$hub` désigne le dossier d'un repo d'agents (clone ou chemin).

```bash
IFS=, read -ra ENTRIES <<< "$CLAUDE_AGENTS_REPOS"
for e in "${ENTRIES[@]}"; do
  nom=${e%%=*}; src=${e#*=}
  case "$src" in
    /*) hub=$src ;;
    *)  hub=~/.claude/agents-repos/$nom
        [ -d "$hub/.git" ] || git clone --filter=blob:none --sparse "$src" "$hub" ;;
  esac
done
```

`CLAUDE_AGENTS_PUSH` liste (virgules) les noms des repos où tu peux écrire et
pousser librement. Les autres sont en **lecture seule**. Si elle est absente,
aucun repo n'est inscriptible : propose alors à l'utilisateur de la définir.

### Au début de chaque session

Avant de traiter la première demande, fais ces vérifications, rapidement et
sans bruit : ne dis rien s'il n'y a rien de nouveau.

**1. Mises à jour (si la dernière vérification est trop ancienne).**
La date de la dernière vérification de chaque repo est dans
`~/.claude/agents-repos/state.tsv` (une ligne `<nom>\t<date ISO 8601 UTC>`).
Si elle est absente ou plus vieille que `CLAUDE_AGENTS_CHECK_HOURS` heures
(défaut 24) :

```bash
git -C "$hub" fetch --quiet
git -C "$hub" log --oneline HEAD..@{u}            # ce qui est nouveau
git -C "$hub" log --oneline HEAD..@{u} -- <projet> # ce qui concerne le projet lancé
```

- Clone (`~/.claude/agents-repos/…`) : `git -C "$hub" pull --rebase --quiet`.
- Chemin local : `git -C "$hub" pull --ff-only --quiet` seulement si la copie
  est propre (`git status --porcelain` vide) ; sinon ne touche à rien et
  signale qu'elle est en retard.
- Enregistre la date du jour pour ce repo dans `state.tsv` (remplace la
  ligne existante), même s'il n'y avait rien de nouveau.
- Si des commits concernent le projet lancé, résume-les en une ou deux
  lignes (agents ajoutés ou modifiés, contexte mis à jour), relis son
  `CLAUDE.md` et lie les nouveaux agents (voir « Récupérer »).

Un repo sans remote ou injoignable (pas de réseau, accès refusé) : signale-le
en une ligne et continue, sans enregistrer de date.

**2. Agents manquants.** Repère les repos git du projet lancé : le dossier de
lancement s'il est un repo, sinon ses sous-dossiers directs qui en sont. Un
repo **a un agent** si `~/.claude/agents/<repo>.md` est un lien valide ou si
`<lancement>/.claude/agents/<repo>.md` existe. Pour chaque repo sans agent,
cherche dans les repos d'agents, sans rien télécharger :

```bash
git -C "$hub" ls-tree -r --name-only HEAD | grep -E "^[^/]+/agents/<repo>\.md$"
```

Préfère le projet du même nom que le dossier de lancement, puis l'ordre de
`CLAUDE_AGENTS_REPOS`. Si tu trouves, récupère-le (voir ci-dessous) et dis-le
en une ligne. Sinon, ne fais rien : l'agent sera créé au premier travail
significatif sur ce repo (« Quand l'écrire »).

Lis aussi `<hub>/<projet>/CLAUDE.md` si le projet lancé existe dans un repo
d'agents.

### Récupérer

Quand l'utilisateur demande des agents (« les agents de X », « l'agent api
de X », « l'agent api de X dans equipe »), ou quand la vérification de
début de session en trouve :

1. Cherche le projet : `git -C "$hub" ls-tree -d --name-only HEAD` dans
   chaque repo. Si l'utilisateur nomme un repo, cherche seulement dans
   celui-là. Si le projet existe dans plusieurs repos, demande lequel
   (indique le premier de la liste comme choix par défaut).
2. Si `$hub` est un clone, télécharge ce projet : `git -C "$hub" sparse-checkout add <projet>`.
3. Lis `<hub>/<projet>/CLAUDE.md` pour le contexte.
4. Rends les agents utilisables par lien symbolique :
   `ln -s "$hub/<projet>/agents/<repo>.md" ~/.claude/agents/<repo>.md`
   (crée `~/.claude/agents/` si besoin). Si le lien existe déjà vers un
   autre fichier, ne l'écrase pas : demande, ou utilise un nom préfixé.
   Les subagents sont chargés au démarrage : préviens l'utilisateur qu'il
   faut relancer claude-docker pour déléguer à un agent nouvellement lié ;
   d'ici là, lis le fichier toi-même.

Si on ne demande qu'un agent précis, ne lie que celui-là, mais lis quand même
le `CLAUDE.md` du projet. Ne télécharge jamais tout un clone
(`sparse-checkout disable`) sans demande explicite.

Pour lister ce qui est disponible : projets de chaque repo et, pour un
projet, `git -C "$hub" ls-tree -r --name-only HEAD -- <projet>` (sans
rien télécharger).

### Écrire et publier

- Mets à jour un projet là où il se trouve, si ce repo est inscriptible.
- Nouveau projet : dans le premier repo de `CLAUDE_AGENTS_PUSH`, sauf si
  l'utilisateur en désigne un autre.
- Projet d'un repo en lecture seule : ne le modifie pas ; propose de le
  copier dans un repo inscriptible, ou de pousser après accord.
- Clone : avant de créer un nouveau dossier, `git -C "$hub" sparse-checkout
  add <projet>` (sinon git refuse de l'ajouter).
- Chemin local : c'est la copie de travail de l'utilisateur. N'ajoute et ne
  commite que les fichiers que tu as modifiés (`git add <fichiers>`, jamais
  `-A`), ne touche pas à ses modifications en cours ni à sa branche.
- Après chaque création ou mise à jour : `git -C "$hub" add <fichiers>`,
  commit (message court : `<projet>: <ce qui change>`), `pull --rebase`,
  `push`. Sans remote, commit seulement.
- **Push autorisé sans demander** sur la branche par défaut des repos de
  `CLAUDE_AGENTS_PUSH`, et uniquement ceux-là. Pas de `--force` ; en cas de
  conflit, résous-le en gardant les deux apports, ou demande.
- Si un repo est vide, initialise-le : `README.md` à la racine décrivant la
  structure (`<projet>/CLAUDE.md`, `<projet>/agents/<repo>.md`), commit, push
  (seulement s'il est inscriptible).
- Ne copie jamais les agents dans les repos de code du projet.

## Git : push

Ne fais jamais de `git push` (ni rien qui publie sur un remote : push de tag,
`--force`, suppression de branche distante, merge de PR) sans l'accord
explicite de l'utilisateur pour ce push-là. Un accord vaut pour la demande en
cours, pas pour les suivantes.

Exceptions :
- les repos d'agents listés dans `CLAUDE_AGENTS_PUSH`, dans les limites décrites plus haut ;
- un repo dont le `CLAUDE.md` ou le fichier d'agent l'indique explicitement
  (ex. « push autorisé sur les branches `claude/*` »). Respecte alors
  exactement le périmètre indiqué et demande pour tout ce qui en sort.

Commits, branches et `fetch`/`pull` locaux restent libres.
