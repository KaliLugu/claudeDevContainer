# claude-docker

Claude Code dans un conteneur Docker, lancé depuis n'importe quel dossier qui
devient le projet de travail.

## Prérequis

- Docker
- fish ou bash (pour la fonction shell ; le script marche aussi seul)
- Un token Claude Code : `claude setup-token` sur une machine où Claude est installé

## Installation

```bash
git clone <ce-repo> ~/claude-docker
cd ~/claude-docker
cp .env.template .env        # puis renseigner CLAUDE_CODE_OAUTH_TOKEN
./install-fish.sh            # ou : ./install-bash.sh
```

`install-fish.sh` installe :

- `~/.config/fish/functions/claude-docker.fish` (lien vers `fish/claude-docker.fish`)
- `~/.config/fish/conf.d/claude-docker.fish` : définit `CLAUDE_DOCKER_REPO` et l'abréviation `clauded`

`install-bash.sh` ajoute à `~/.bashrc` un bloc qui définit `CLAUDE_DOCKER_REPO`
et source `bash/claude-docker.bash` (fonction `claude-docker` + alias
`clauded`). Relançable : le bloc existant est remplacé.

Ouvre un nouveau shell.

## Utilisation

```fish
cd ~/projets/mon-projet
claude-docker                # ou : clauded
claude-docker --continue     # les arguments sont passés à claude
claude-docker --rebuild      # reconstruit l'image avant de lancer
```

Sans fonction shell : `~/claude-docker/bin/claude-docker`.

### Ce que fait le lancement

| Élément | Détail |
|---|---|
| Image | `claude-code`, construite au premier lancement avec ton UID/GID (les fichiers créés t'appartiennent) |
| Projet | le dossier courant, monté **au même chemin** que sur l'hôte (historique Claude séparé par projet) |
| Config Claude | volume Docker `claude-config` → `/home/dev/.claude` (session, réglages, historique persistants) |
| Règles globales | `config/CLAUDE.md` monté en lecture seule comme `~/.claude/CLAUDE.md` |
| Secrets | `.env` du repo passé via `--env-file` |

Seul le dossier courant est visible dans le conteneur : Claude ne peut pas
lire ni modifier le reste de la machine.

Variables optionnelles : `CLAUDE_DOCKER_IMAGE`, `CLAUDE_DOCKER_CONFIG_VOLUME`.

## Clé SSH dédiée à Claude

Pour que Claude puisse cloner, `fetch` ou `pull` des repos privés sans
utiliser ta propre clé :

```bash
~/claude-docker/setup-ssh-key.sh
```

Le script crée `ssh/id_ed25519` dans ce repo (ignoré par git), un
`ssh/config` et un `known_hosts`, puis affiche la clé publique. Ce dossier est
monté comme `~/.ssh` dans le conteneur à chaque lancement. Le script est
relançable : il n'écrase pas une clé existante et réaffiche la clé publique.

Ajoute ensuite la clé publique sur ta forge :

- **Deploy key par repo** (recommandé) : *Settings → Deploy keys*. Laisse
  « Allow write access » décoché si Claude n'a pas à pousser sur ce repo.
- **Clé de compte** : *Settings → SSH and GPG keys*. Plus simple, mais donne
  accès à tous tes repos.

La clé n'a pas de passphrase (Claude ne peut pas la saisir) : donne-lui le
moins de droits possible, et révoque-la côté forge si la machine est
compromise. Pour la changer, supprime `ssh/` et relance le script.

Test depuis le conteneur : `ssh -T git@github.com`.

Pour signer les commits de Claude à ton nom ou à un nom dédié, renseigne les
variables `GIT_AUTHOR_*` / `GIT_COMMITTER_*` dans `.env`.

**Push** : `config/CLAUDE.md` interdit à Claude de pousser sans ton accord
explicite. Pour l'autoriser sur un repo précis, écris-le dans le `CLAUDE.md`
de ce repo (ou dans son fichier d'agent), par exemple :

> Push autorisé sans demander sur les branches `claude/*`.

## Agents spécialisés par repo

`config/CLAUDE.md` contient des règles qui font écrire à Claude, au fil du
travail, un fichier `.md` par repo décrivant ce qu'il faut savoir pour y
travailler : commandes, architecture, conventions, interfaces avec les autres
repos, pièges. Ces fichiers sont au format
[subagent Claude Code](https://docs.claude.com/en/docs/claude-code/sub-agents),
donc directement utilisables comme agents spécialisés.

**C'est opt-in par projet** : les règles ne s'appliquent que si le dossier de
lancement contient `.claude/agents/`.

### Mono-repo

```fish
cd ~/projets/mon-repo
mkdir -p .claude/agents
claude-docker
```

→ `mon-repo/.claude/agents/mon-repo.md`

### Multirepo

Lance depuis le dossier parent qui regroupe les repos, pour que Claude les
voie tous :

```
~/projets/ma-plateforme/          ← lancer claude-docker ici
├── CLAUDE.md                     ← carte des repos et de leurs liens
├── .claude/agents/
│   ├── api.md
│   ├── front.md
│   └── infra.md
├── api/                          (repo git)
├── front/                        (repo git)
└── infra/                        (repo git)
```

```fish
cd ~/projets/ma-plateforme
mkdir -p .claude/agents
claude-docker
```

Le dossier parent n'est en général pas lui-même un repo. Pour versionner et
partager ces fichiers, tu peux en faire un petit repo « méta »
(`git init` dans `ma-plateforme/` en ignorant les sous-repos) ou les copier
dans un repo de doc.

Pour demander une mise à jour explicite :
> Mets à jour l'agent du repo api avec ce qu'on vient d'apprendre.

Pour modifier les règles, édite `config/CLAUDE.md` ; c'est pris en compte au
lancement suivant, sans reconstruire l'image.

## Structure

```
bin/claude-docker         script de lancement
fish/claude-docker.fish   fonction fish
install-fish.sh           installation de la fonction fish
bash/claude-docker.bash   fonction bash
install-bash.sh           installation de la fonction bash
setup-ssh-key.sh          création de la clé SSH dédiée à Claude
config/CLAUDE.md          règles globales montées dans le conteneur
dockerfile                image Claude Code (Debian + installeur natif)
.env.template             variables attendues dans .env
```
