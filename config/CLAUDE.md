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

Ne s'applique que si `CLAUDE_AGENTS_REPOS` est définie : liste
`nom=url` séparés par des virgules, par ordre de priorité. Exemple :
`perso=git@github.com:moi/claude-agents.git,equipe=git@github.com:team/agents.git`.

`CLAUDE_AGENTS_PUSH` liste (virgules) les noms des repos où tu peux écrire et
pousser librement. Les autres sont en **lecture seule**. Si elle est absente,
aucun repo n'est inscriptible : propose alors à l'utilisateur de la définir.

Chaque repo est cloné dans `~/.claude/agents-repos/<nom>` (persistant entre
les lancements), en **clone partiel** : seuls les projets demandés sont
téléchargés.

```bash
IFS=, read -ra ENTRIES <<< "$CLAUDE_AGENTS_REPOS"
for e in "${ENTRIES[@]}"; do
  nom=${e%%=*}; url=${e#*=}; hub=~/.claude/agents-repos/$nom
  [ -d "$hub/.git" ] || git clone --filter=blob:none --sparse "$url" "$hub"
  git -C "$hub" pull --rebase --quiet
done
```

### Trouver et récupérer

Quand l'utilisateur demande des agents (« les agents de X », « l'agent api
de X », « l'agent api de X dans equipe »), ou au début du travail sur un
projet présent dans un repo d'agents :

1. Mets à jour les clones (boucle ci-dessus).
2. Liste les projets : `git -C "$hub" ls-tree -d --name-only HEAD` pour
   chaque repo. Si l'utilisateur nomme un repo, cherche seulement dans
   celui-là. Si le projet existe dans plusieurs repos, demande lequel
   (indique le premier de la liste comme choix par défaut).
3. Télécharge ce projet seulement : `git -C "$hub" sparse-checkout add <projet>`.
4. Lis `<hub>/<projet>/CLAUDE.md` pour le contexte.
5. Rends les agents demandés utilisables par lien symbolique :
   `ln -s "$hub/<projet>/agents/<repo>.md" ~/.claude/agents/<repo>.md`
   (crée `~/.claude/agents/` si besoin). Si le lien existe déjà vers un
   autre fichier, ne l'écrase pas : demande, ou utilise un nom préfixé.
   Les subagents sont chargés au démarrage : préviens l'utilisateur qu'il
   faut relancer claude-docker pour déléguer à un agent nouvellement lié ;
   d'ici là, lis le fichier toi-même.

Si on ne demande qu'un agent précis, ne lie que celui-là, mais lis quand même
le `CLAUDE.md` du projet. Ne télécharge jamais tout un repo
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
- Avant de créer un nouveau dossier : `git -C "$hub" sparse-checkout add
  <projet>` (sinon git refuse de l'ajouter).
- Après chaque création ou mise à jour : `git -C "$hub" add <projet>`,
  commit (message court : `<projet>: <ce qui change>`), `pull --rebase`,
  `push`.
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
