# Journal des changements

Ce qui change pour ceux qui utilisent claude-docker, du plus récent au plus
ancien. Les changements de comportement, ceux qui demandent une action ou
peuvent surprendre après un `git pull`, sont en tête de chaque entrée.

## 2026-11-27

### Changements de comportement

- **Push** : tout `git push` et tout merge de PR demandent maintenant ton
  accord dans le terminal, par un hook, quel que soit le mode de permission.
  Un push lancé depuis un script ou un outil est refusé.
- **Exceptions de push** : un `CLAUDE.md` de repo ne peut plus autoriser un
  push. Utilise `CLAUDE_PUSH_ALLOW=repo:branche` dans `.env`
  (ex. `api:claude/*`).
- **`sudo`** : Claude a `sudo` sans mot de passe dans le conteneur.
  `claude-docker --no-sudo` lance une session sans `sudo` ni privilèges.
- **Clé SSH** : `ssh/` est monté en lecture seule. Si ton `ssh/config` date
  d'avant, supprime-le et relance `setup-ssh-key.sh` (la clé est conservée).
- **Mise à jour de Claude Code** : elle ne se fait plus dans le conteneur.
- **Reconstruction** : l'image est reconstruite d'elle-même au premier
  lancement après un changement du `dockerfile`.
- **Repos d'agents** : la synchronisation est faite par un script avant le
  démarrage de Claude, plus par Claude lui-même. `state.tsv` change de format
  (les anciennes dates sont ignorées, une vérification est refaite).

### Ajouts

- `mise` dans l'image : langages et outils installés sans root, conservés
  dans le volume `claude-tools`.
- `.claude-docker/packages` dans un projet : paquets `apt` installés dans une
  image dérivée. `claude-docker --clean` supprime ces images.
- Avertissements au lancement pour les réglages de `.env` mal écrits ;
  `CLAUDE_DOCKER_ENV_FILE` pour utiliser un autre fichier.
- Tests (`tests/`) et CI GitHub Actions.
- Licence MIT.

### Corrections

- Le build échouait sur macOS (GID 20 déjà pris dans Debian).
- `--rebuild` réutilisait le cache et ne réinstallait rien.
- L'entrée par pipe (`echo … | claude-docker -p`) n'était pas transmise.
- Capacités Linux du conteneur réduites, nombre de processus limité.
- Le README décrit ce que le conteneur ne protège pas : projet monté en
  écriture, réseau ouvert, volumes partagés.
