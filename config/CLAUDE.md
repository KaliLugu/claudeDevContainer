# Règles globales (conteneur claude-docker)

## Agents spécialisés par repo

`~/.claude/agents/` est monté depuis le repo claudeDevContainer (dossier
`agents/`) : tout ce que tu y écris est conservé et versionné là-bas, et
chaque fichier est disponible comme subagent dans **tous** les projets.

### Quand écrire

- **Création** : uniquement si l'utilisateur le demande (« crée / sauvegarde
  l'agent de ce repo »). Ne crée jamais d'agent de ta propre initiative.
- **Mise à jour** : si un agent existe déjà pour le repo courant, mets-le à
  jour quand tu découvres quelque chose de non évident et durable (commande
  qui ne marche que d'une certaine façon, couplage entre repos, convention
  implicite, piège qui t'a coûté du temps).
- Signale à l'utilisateur, en une ligne, chaque fichier créé ou modifié.

### Où et comment nommer

- Un fichier par repo : `~/.claude/agents/<nom-du-repo>.md`, `name` identique.
  Le nom du repo vient du remote git (`git remote get-url origin`), sinon du
  nom du dossier. En cas de collision avec un agent d'un autre repo, préfixe
  par l'organisation : `<org>-<repo>`.
- **Multirepo** (lancé depuis un dossier parent contenant plusieurs repos) :
  un agent par sous-repo, plus un agent coordinateur
  `~/.claude/agents/<nom-du-dossier-parent>.md` qui liste les repos (chemin,
  rôle en une ligne, agent associé) et leurs liens (qui appelle qui, contrats
  partagés, ordre de déploiement).
- Ne mets dans ce dossier que des fichiers d'agent : tout `.md` y est chargé
  comme subagent.

### Format

```markdown
---
name: <nom-du-repo>
description: Expert du repo <nom-du-repo> (<remote git>). À utiliser pour <cas d'usage concrets>.
---

Tu es spécialiste du repo `<nom-du-repo>` (<remote git>).

## Rôle
## Stack et commandes (build, test, lint, lancement)
## Architecture (dossiers clés, points d'entrée)
## Conventions (style, nommage, branches, commits)
## Interfaces avec les autres repos (API, schémas, events, libs partagées)
## Pièges connus
```

N'écris pas de chemins absolus de la machine : le repo peut être ouvert
ailleurs. Décris les chemins relativement à la racine du repo.

### Contenu

- Pas ce qui se lit directement dans le code ou l'historique git, pas de
  détails propres à la tâche en cours, jamais de secrets.
- Modifie la section concernée plutôt que d'empiler ; supprime ce qui est
  devenu faux. Garde chaque fichier court (idéalement < 150 lignes).

### Utilisation

Pour une tâche qui touche un repo précis, délègue à son agent quand c'est
utile ; pour une tâche transverse en multirepo, appuie-toi sur l'agent
coordinateur.
