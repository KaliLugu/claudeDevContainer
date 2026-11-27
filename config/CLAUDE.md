# Règles globales (conteneur claude-docker)

## Mémoire de repo pour agents spécialisés

Claude tient, pour chaque repo, un fichier d'agent décrivant ce qu'il faut
savoir pour y travailler, et pour chaque projet un fichier de contexte. Deux
modes, selon la variable d'environnement `CLAUDE_AGENTS_REPO` :

- **Définie** (URL git) → mode **repo d'agents** : tout vit dans ce repo
  séparé (voir « Repo d'agents » plus bas).
- **Absente** → mode **local** : les règles ne s'appliquent que si le dossier
  de lancement contient `.claude/agents/` (opt-in), ou si l'utilisateur le
  demande. Sinon, ne crée aucun de ces fichiers.

### Projet et fichiers

Un **projet** est ce sur quoi on lance claude-docker : un repo seul
(mono-repo) ou un dossier parent regroupant plusieurs repos (multirepo). Son
nom est le nom du dossier de lancement, sauf indication de l'utilisateur.

| Fichier | Mode local | Mode repo d'agents |
|---|---|---|
| Agent d'un repo | `<lancement>/.claude/agents/<repo>.md` | `<hub>/<projet>/agents/<repo>.md` |
| Contexte du projet | `<lancement>/CLAUDE.md` (multirepo seulement) | `<hub>/<projet>/CLAUDE.md` |

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

Le `name` doit être unique dans tout le repo d'agents : en cas de collision
entre deux projets, préfixe-le par le projet (`<projet>-<repo>`), ainsi que
le nom du fichier.

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

## Repo d'agents

Ne s'applique que si `CLAUDE_AGENTS_REPO` est définie. Le repo est cloné dans
`~/.claude/agents-repo` (le « hub », persistant entre les lancements), en
**clone partiel** : seuls les projets demandés sont téléchargés.

### Récupérer un projet

Quand l'utilisateur demande les agents d'un projet, ou au début du travail
sur un projet qui existe dans le hub :

```bash
HUB=~/.claude/agents-repo
[ -d "$HUB/.git" ] || git clone --filter=blob:none --sparse "$CLAUDE_AGENTS_REPO" "$HUB"
git -C "$HUB" pull --rebase --quiet
git -C "$HUB" ls-tree -d --name-only HEAD     # projets disponibles
git -C "$HUB" sparse-checkout add <projet>    # télécharge ce projet seulement
```

Puis :
1. Lis `<hub>/<projet>/CLAUDE.md` pour le contexte.
2. Rends ses agents utilisables par lien symbolique :
   `ln -sf "$HUB/<projet>/agents/<repo>.md" ~/.claude/agents/<repo>.md`
   (crée `~/.claude/agents/` si besoin). Les subagents sont chargés au
   démarrage : préviens l'utilisateur qu'il faut relancer claude-docker pour
   déléguer à un agent nouvellement lié ; d'ici là, lis le fichier toi-même.

Si on ne demande qu'un agent précis, ne lie que celui-là, mais lis quand même
le `CLAUDE.md` du projet. Ne télécharge jamais tout le repo (`sparse-checkout
disable`) sans demande explicite.

Si le repo est vide, initialise-le : `README.md` à la racine décrivant la
structure ci-dessus, commit, push.

### Écrire et publier

- Nouveau projet : `git -C "$HUB" sparse-checkout add <projet>` **avant** de
  créer le dossier (sinon git refuse de l'ajouter).
- Après chaque création ou mise à jour : `git -C "$HUB" add <projet>`, commit
  (message court : `<projet>: <ce qui change>`), `pull --rebase`, `push`.
- **Push autorisé sans demander** sur la branche par défaut de ce repo, et
  uniquement celui-ci. Pas de `--force` ; en cas de conflit, résous-le en
  gardant les deux apports, ou demande.
- Ne copie jamais les agents dans les repos de code du projet.

## Git : push

Ne fais jamais de `git push` (ni rien qui publie sur un remote : push de tag,
`--force`, suppression de branche distante, merge de PR) sans l'accord
explicite de l'utilisateur pour ce push-là. Un accord vaut pour la demande en
cours, pas pour les suivantes.

Exceptions :
- le repo d'agents (`CLAUDE_AGENTS_REPO`), dans les limites décrites plus haut ;
- un repo dont le `CLAUDE.md` ou le fichier d'agent l'indique explicitement
  (ex. « push autorisé sur les branches `claude/*` »). Respecte alors
  exactement le périmètre indiqué et demande pour tout ce qui en sort.

Commits, branches et `fetch`/`pull` locaux restent libres.
