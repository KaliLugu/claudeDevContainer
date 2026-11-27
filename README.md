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

GitHub n'accepte une même clé comme deploy key que sur **un seul** repo. Pour
plusieurs repos, utilise la clé de compte (ou un compte GitHub dédié à
Claude, invité en collaborateur sur les repos voulus).

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

Deux modes :

- **Local** (par défaut) : opt-in par projet, les fichiers sont écrits dans le
  dossier de lancement s'il contient `.claude/agents/`. Voir ci-dessous.
- **Repos d'agents** : si `CLAUDE_AGENTS_REPOS` est défini dans `.env`, tout est
  rangé dans un ou plusieurs repos git séparés. Voir [Repos d'agents](#repos-dagents).

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

Le dossier parent n'est en général pas lui-même un repo : pour versionner et
partager ces fichiers, utilise plutôt le mode repos d'agents.

Pour demander une mise à jour explicite :
> Mets à jour l'agent du repo api avec ce qu'on vient d'apprendre.

### Repos d'agents

Tes agents et contextes de projets vivent dans un ou plusieurs repos séparés
de claude-docker : ceux qui utilisent claude-docker ne les récupèrent pas, et
tes repos de code restent propres. Tu peux combiner ton repo perso, celui de
ton équipe, celui de quelqu'un d'autre…

Chaque repo d'agents a la même structure, un dossier par projet :

```
claude-agents/                    (privé de préférence)
├── README.md
├── ma-plateforme/
│   ├── CLAUDE.md                 contexte : repos, rôles, liens
│   └── agents/
│       ├── api.md
│       ├── front.md
│       └── infra.md
└── mon-repo/
    ├── CLAUDE.md
    └── agents/mon-repo.md
```

Mise en place :

1. Crée un repo vide sur ta forge (ex. `claude-agents`).
2. Donne à la clé SSH de Claude l'accès à chaque repo : **en écriture** pour
   ceux où Claude doit publier, en lecture pour les autres.
3. Dans `.env`, sans espaces ni guillemets :
   ```
   CLAUDE_AGENTS_REPOS=perso=git@github.com:<toi>/claude-agents.git,equipe=git@github.com:<equipe>/agents.git
   CLAUDE_AGENTS_PUSH=perso
   ```
   `CLAUDE_AGENTS_REPOS` : liste `nom=url`, l'ordre donne la priorité quand
   un projet existe dans plusieurs repos. `CLAUDE_AGENTS_PUSH` : les repos où
   Claude écrit et pousse librement ; les autres sont en lecture seule.
4. Relance claude-docker.

Fonctionnement :

- Chaque repo est cloné dans le volume de config
  (`~/.claude/agents-repos/<nom>`), en **clone partiel** : seuls les projets
  demandés sont téléchargés.
- Claude **pousse librement** sur les repos de `CLAUDE_AGENTS_PUSH` (branche
  par défaut, sans `--force`) ; c'est la seule exception automatique à la
  règle « pas de push sans accord ». Les nouveaux projets vont dans le
  premier de cette liste. Un projet d'un repo en lecture seule n'est pas
  modifié : Claude propose de le copier dans un repo inscriptible.
- Les agents récupérés sont liés dans `~/.claude/agents/` et deviennent
  disponibles dans tous les projets **au lancement suivant**.

Exemples de demandes :
> Récupère les agents de ma-plateforme.
> Récupère seulement l'agent api de ma-plateforme dans equipe.
> Quels projets sont disponibles dans mes repos d'agents ?

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
