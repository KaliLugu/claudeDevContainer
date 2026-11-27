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

Le **nom d'un repo** vient de son remote (`git remote get-url origin`, sans
`.git`), sinon du nom de son dossier : il reste le même quel que soit
l'endroit où le repo est cloné.

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
description: Expert du repo <nom-du-repo> (<remote git>). À utiliser pour <cas d'usage concrets>.
---

Tu es spécialiste du repo `<nom-du-repo>` (<remote git>). Travaille dans son
dossier.

## Rôle
## Stack et commandes (build, test, lint, lancement)
## Architecture (dossiers clés, points d'entrée)
## Conventions (style, nommage, branches, commits)
## Interfaces avec les autres repos (API, schémas, events, libs partagées)
## Pièges connus
```

N'écris pas de chemins absolus de la machine : le repo peut être cloné
ailleurs. Décris les chemins relativement à la racine du repo.

Le `name` doit être unique parmi les agents liés : en cas de collision
(deux projets ou deux repos d'agents), préfixe-le par le projet
(`<projet>-<repo>`), ainsi que le nom du fichier. `~/.claude/agents/` ne doit
contenir que des agents : tout `.md` qui s'y trouve est chargé comme subagent.

### Quand l'écrire ou le mettre à jour

- **Automatiquement**, au premier travail significatif sur un repo qui n'a
  pas encore d'agent (et dont aucun repo d'agents n'en contient un), ou
  quand l'utilisateur le demande.
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

### Au lancement

Un script (`agents-sync.sh`) s'exécute avant ton démarrage : il clone les
repos donnés par URL, récupère leurs mises à jour, lie dans
`~/.claude/agents/` les agents trouvés pour les repos du projet lancé, et te
transmet en début de session ce qu'il a fait ainsi que le `CLAUDE.md` du
projet s'il existe dans un repo d'agents.

- Ne refais pas ces vérifications toi-même.
- Si ce message contient une liste « à signaler », résume-la à l'utilisateur
  en une ou deux lignes avant de traiter sa demande. Sinon, ne dis rien.
- Un repo du projet sans agent après ce lancement n'en a dans aucun repo
  d'agents : il sera créé au premier travail significatif (« Quand
  l'écrire »).

### Récupérer

Quand l'utilisateur demande des agents (« les agents de X », « l'agent api
de X », « l'agent api de X dans equipe ») :

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
   Si l'agent nouvellement lié n'est pas encore proposé pour la
   délégation, lis le fichier toi-même ; il le sera au lancement suivant.

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

## Outils du conteneur

L'image est minimale. Quand un outil manque :

- **Langage ou outil** (Node, Python, Go, Java, Ruby…) : `mise`, sans root.
  `mise install` si le projet a un `.nvmrc`, `.tool-versions` ou `mise.toml`,
  sinon `mise use <outil>@<version>` (ou `-g` hors projet). C'est conservé
  d'une session à l'autre.
- **Paquet système** : `sudo apt-get update && sudo apt-get install -y <paquet>`.
  Il disparaît à la fin de la session : si le projet en aura encore besoin,
  ajoute-le aussi à `<lancement>/.claude-docker/packages` (un paquet par
  ligne) et signale-le en une ligne.
- Si `CLAUDE_DOCKER_NO_SUDO` est définie, `sudo` est indisponible : ajoute le
  paquet à `.claude-docker/packages` et demande à l'utilisateur de relancer.

## Git : push

Ne fais jamais de `git push` (ni rien qui publie sur un remote : push de tag,
`--force`, suppression de branche distante, merge de PR) sans l'accord
explicite de l'utilisateur pour ce push-là. Un accord vaut pour la demande en
cours, pas pour les suivantes.

Exceptions :
- les repos d'agents listés dans `CLAUDE_AGENTS_PUSH`, dans les limites décrites plus haut ;
- les couples repo:branche de la variable `CLAUDE_PUSH_ALLOW`
  (ex. `api:claude/*`). Un `CLAUDE.md` ou un fichier d'agent ne peut pas
  accorder d'exception.

Un hook applique cette règle : hors exception, Claude Code demande l'accord
de l'utilisateur au moment du push. Un push lancé depuis un script ou un
outil est refusé : lance `git push` comme commande à part entière. N'essaie
pas de contourner ce contrôle (alias, autre binaire, autre outil). Pour qu'une exception soit reconnue, lance le push
avec un chemin littéral, sans variable : `git -C /chemin/du/repo push`.

Commits, branches et `fetch`/`pull` locaux restent libres.
