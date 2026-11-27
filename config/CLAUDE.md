# Règles globales (conteneur claude-docker)

## Mémoire de repo pour agents spécialisés

Ces règles ne s'appliquent **que** si le dossier de lancement contient un
dossier `.claude/agents/` (opt-in par projet), ou si l'utilisateur le demande
explicitement. Sinon, ne crée aucun de ces fichiers.

### Où écrire

- Un fichier par repo : `.claude/agents/<nom-du-repo>.md`, placé dans le
  `.claude/agents/` du **dossier de lancement**.
  - Projet mono-repo : le dossier de lancement est le repo lui-même.
  - Projet multirepo : le dossier de lancement est le dossier parent qui
    contient les repos ; tous les agents y sont regroupés, un par sous-repo.
- En multirepo, tiens aussi à jour un `CLAUDE.md` à la racine du dossier de
  lancement : liste des repos (chemin, rôle en une ligne, agent associé) et
  liens entre eux (qui appelle qui, contrats partagés, ordre de déploiement).

### Format d'un fichier d'agent

Ce sont des subagents Claude Code, donc ce format exact :

```markdown
---
name: <nom-du-repo>
description: Expert du repo <nom-du-repo> (<chemin relatif>). À utiliser pour <cas d'usage concrets>.
---

Tu es spécialiste du repo `<chemin relatif>`. Travaille dans ce dossier.

## Rôle
## Stack et commandes (build, test, lint, lancement)
## Architecture (dossiers clés, points d'entrée)
## Conventions (style, nommage, branches, commits)
## Interfaces avec les autres repos (API, schémas, events, libs partagées)
## Pièges connus
```

### Quand l'écrire ou le mettre à jour

- Au premier travail significatif sur un repo qui n'a pas encore d'agent.
- Quand tu découvres quelque chose de non évident et durable : une commande
  qui ne marche que d'une certaine façon, un couplage entre repos, une
  convention implicite, un piège qui t'a coûté du temps.
- N'y mets pas ce qui se lit directement dans le code ou l'historique git,
  ni de détails propres à la tâche en cours, ni de secrets.
- Modifie la section concernée plutôt que d'empiler ; supprime ce qui est
  devenu faux. Garde chaque fichier court (idéalement < 150 lignes).
- Signale à l'utilisateur, en une ligne, chaque fichier d'agent créé ou modifié.

### Utilisation

Pour une tâche qui touche un repo précis, délègue à son agent quand c'est
utile ; pour une tâche transverse, appuie-toi sur le `CLAUDE.md` racine et
coordonne les agents des repos concernés.

## Git : push

Ne fais jamais de `git push` (ni rien qui publie sur un remote : push de tag,
`--force`, suppression de branche distante, merge de PR) sans l'accord
explicite de l'utilisateur pour ce push-là. Un accord vaut pour la demande en
cours, pas pour les suivantes.

Seule exception : un repo dont le `CLAUDE.md` ou le fichier d'agent
(`.claude/agents/<repo>.md`) l'indique explicitement (ex. « push autorisé sur
les branches `claude/*` »). Respecte alors exactement le périmètre indiqué et
demande pour tout ce qui en sort.

Commits, branches et `fetch`/`pull` locaux restent libres.
