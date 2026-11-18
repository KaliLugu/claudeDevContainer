# claude-docker

Claude Code dans un conteneur Docker, lancé depuis n'importe quel dossier qui
devient le projet de travail.

## Prérequis

- Docker
- fish (pour la fonction shell ; le script marche aussi depuis bash/zsh)
- Un token Claude Code : `claude setup-token` sur une machine où Claude est installé

## Installation

```bash
git clone <ce-repo> ~/claude-docker
cd ~/claude-docker
cp .env.template .env        # puis renseigner CLAUDE_CODE_OAUTH_TOKEN
./install-fish.sh
```

`install-fish.sh` installe :

- `~/.config/fish/functions/claude-docker.fish` (lien vers `fish/claude-docker.fish`)
- `~/.config/fish/conf.d/claude-docker.fish` : définit `CLAUDE_DOCKER_REPO` et l'abréviation `clauded`

Ouvre un nouveau shell fish.

## Utilisation

```fish
cd ~/projets/mon-projet
claude-docker                # ou : clauded
claude-docker --continue     # les arguments sont passés à claude
claude-docker --rebuild      # reconstruit l'image avant de lancer
```

Sans fish : `~/claude-docker/bin/claude-docker`.

### Windows (PowerShell + Docker Desktop)

Prérequis : Docker Desktop lancé, en mode *Linux containers*.

```powershell
git clone <ce-repo> $HOME\claude-docker
cd $HOME\claude-docker
Copy-Item .env.template .env          # puis renseigner CLAUDE_CODE_OAUTH_TOKEN
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned   # une seule fois

cd C:\chemin\vers\mon-projet
& $HOME\claude-docker\bin\claude-docker.ps1            # mêmes options : --rebuild, --continue…
```

Pour avoir la commande `claude-docker` partout, ajoute à ton profil
(`notepad $PROFILE`) :

```powershell
function claude-docker { & "$HOME\claude-docker\bin\claude-docker.ps1" @args }
```

Le projet `C:\Users\moi\projet` est monté dans le conteneur en
`/c/Users/moi/projet`. Les montages depuis NTFS sont plus lents que sous
Linux ; pour de gros projets, préfère WSL2 avec le script bash.

### Ce que fait le lancement

| Élément | Détail |
|---|---|
| Image | `claude-code`, construite au premier lancement avec ton UID/GID (les fichiers créés t'appartiennent) |
| Projet | le dossier courant, monté **au même chemin** que sur l'hôte (historique Claude séparé par projet) |
| Config Claude | volume Docker `claude-config` → `/home/dev/.claude` (session, réglages, historique persistants) |
| Règles globales | `config/CLAUDE.md` monté en lecture seule comme `~/.claude/CLAUDE.md` |
| Agents | `agents/` du repo monté comme `~/.claude/agents/` (lecture-écriture) |
| Secrets | `.env` du repo passé via `--env-file` |

Seul le dossier courant est visible dans le conteneur : Claude ne peut pas
lire ni modifier le reste de la machine.

Variables optionnelles : `CLAUDE_DOCKER_IMAGE`, `CLAUDE_DOCKER_CONFIG_VOLUME`.

## Agents spécialisés par repo

Depuis n'importe quel projet lancé avec `claude-docker`, tu peux demander à
Claude d'écrire un agent spécialisé pour ce repo. Il est enregistré dans le
dossier `agents/` **de ce repo-ci** (monté comme `~/.claude/agents/` dans le
conteneur) : il est donc versionné ici et disponible comme
[subagent Claude Code](https://docs.claude.com/en/docs/claude-code/sub-agents)
dans tous tes projets.

Les règles sont dans `config/CLAUDE.md`.

### Mono-repo

```fish
cd ~/projets/mon-repo
claude-docker
```
> Crée l'agent de ce repo.

→ `claudeDevContainer/agents/mon-repo.md`

Ensuite, Claude le tient à jour tout seul quand il découvre quelque chose de
durable (commandes, conventions, pièges, liens avec d'autres repos). Pour
forcer une mise à jour :
> Mets à jour l'agent de ce repo avec ce qu'on vient d'apprendre.

### Multirepo

Lance depuis le dossier parent qui regroupe les repos, pour que Claude les
voie tous :

```
~/projets/ma-plateforme/      ← lancer claude-docker ici
├── api/                      (repo git)
├── front/                    (repo git)
└── infra/                    (repo git)
```
> Crée les agents de ces repos.

→ dans `claudeDevContainer/agents/` : `api.md`, `front.md`, `infra.md`, plus
`ma-plateforme.md`, un agent coordinateur qui décrit les liens entre les repos.

### Versionner

Les fichiers apparaissent dans `agents/` de ce repo ; commite-les comme le
reste :

```bash
cd ~/claude-docker
git add agents && git commit -m "Agents : api, front, infra"
```

Pour modifier les règles, édite `config/CLAUDE.md` ; c'est pris en compte au
lancement suivant, sans reconstruire l'image.


## Structure

```
bin/claude-docker         script de lancement (bash)
bin/claude-docker.ps1     script de lancement (PowerShell, Windows)
fish/claude-docker.fish   fonction fish
install-fish.sh           installation de la fonction fish
config/CLAUDE.md          règles globales montées dans le conteneur
agents/                   agents spécialisés par repo, écrits par Claude
dockerfile                image Claude Code (Debian + installeur natif)
.env.template             variables attendues dans .env
```
