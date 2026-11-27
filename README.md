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
claude-docker --rebuild      # reconstruit l'image sans cache (paquets Debian à jour)
                             # (l'image est aussi reconstruite seule quand le dockerfile change)
claude-docker --no-sudo      # session sans sudo ni privilèges (voir Outils)
claude-docker --clean        # supprime les images de paquets de projet (voir Outils)
echo "résume ce repo" | claude-docker -p    # l'entrée par pipe est transmise
```

Sans fonction shell : `~/claude-docker/bin/claude-docker`.

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

Sous Windows natif, la clé SSH dédiée et les repos d'agents donnés par un
chemin local ne sont pas pris en charge (les repos d'agents par URL git
fonctionnent) : pour tout avoir, utilise WSL2 avec le script bash.

### Ce que fait le lancement

| Élément | Détail |
|---|---|
| Image | `claude-code`, construite au premier lancement avec ton UID/GID (les fichiers créés t'appartiennent) |
| Projet | le dossier courant, monté **au même chemin** que sur l'hôte (historique Claude séparé par projet) |
| Config Claude | volume Docker `claude-config` → `/home/dev/.claude` (session, réglages, historique persistants) |
| Outils | volume Docker `claude-tools` → `~/.local/share/mise` (langages installés par `mise`, persistants) |
| Paquets du projet | `.claude-docker/packages` du dossier courant, installés dans une image dérivée |
| Règles globales | `config/CLAUDE.md` monté en lecture seule comme `~/.claude/CLAUDE.md` |
| Réglages imposés | `config/managed/` monté en lecture seule comme `/etc/claude-code` (hook de contrôle des push) |
| Clé SSH | `ssh/` monté en lecture seule comme `~/.ssh` s'il contient une clé (`setup-ssh-key.sh`) |
| Repos d'agents | ceux de `CLAUDE_AGENTS_REPOS` donnés par un chemin local, montés au même chemin |
| Secrets | `.env` du repo passé via `--env-file` |

### Ce que le conteneur protège, et ce qu'il ne protège pas

Pendant la session, Claude ne voit que le dossier courant (et les repos
d'agents montés) : il ne peut ni lire ni modifier le reste de la machine.

Trois limites à connaître :

- **Le projet est monté en écriture, `.git` compris.** Ce que Claude y écrit
  s'exécutera sur ta machine si tu le lances : un hook git, un script de
  `package.json`, un `Makefile`, un fichier `.husky/`. Relis le diff
  (`git status`, `git diff`, et `.git/hooks` en cas de doute) avant
  d'exécuter quoi que ce soit après une session sans surveillance.
- **Le réseau est ouvert.** Ce qui tourne dans le conteneur peut joindre
  Internet, donc faire sortir le code du projet, le token Claude et la clé
  SSH dédiée. Donne à cette clé le moins de droits possible.
- **Les volumes `claude-config` et `claude-tools` sont partagés** entre tous
  tes projets : ce qu'une session y dépose est vu par les suivantes.
  `CLAUDE_DOCKER_CONFIG_VOLUME` et `CLAUDE_DOCKER_TOOLS_VOLUME` permettent
  d'en utiliser d'autres pour un projet sensible.

Variables optionnelles : `CLAUDE_DOCKER_IMAGE`, `CLAUDE_DOCKER_CONFIG_VOLUME`,
`CLAUDE_DOCKER_TOOLS_VOLUME`, `CLAUDE_DOCKER_ENV_FILE` (un autre fichier que
`.env`).

Au lancement, le script signale sur le terminal les réglages de `.env` qu'il
ne comprend pas (entrée mal formée, guillemets, nom de repo inconnu, token
vide), puis continue.

## Versions

Les versions de Claude Code et de `mise` sont fixées en tête du `dockerfile`
(`CLAUDE_VERSION`, `MISE_VERSION`) : deux builds donnent la même image, et
le binaire `mise` est vérifié par son empreinte SHA-256. Claude Code ne se
met pas à jour seul dans le conteneur.

Pour mettre à jour :

```bash
scripts/update-versions.sh           # écrit les dernières versions et empreintes
scripts/update-versions.sh --check   # dit seulement s'il y en a de nouvelles
```

L'image est reconstruite au lancement suivant. Sur GitHub, un workflow
hebdomadaire (`.github/workflows/update-versions.yml`) lance ce script,
teste l'image et ouvre une PR. Il faut l'y autoriser une fois : *Settings →
Actions → General → Allow GitHub Actions to create and approve pull
requests*.

Pour essayer une autre version de Claude Code sans toucher au fichier :

```bash
CLAUDE_DOCKER_CLAUDE_VERSION=latest claude-docker --rebuild
```

L'image de base `debian:bookworm-slim` n'est pas figée, pour continuer à
recevoir les correctifs de sécurité à chaque `--rebuild`.

## Outils

L'image de base est volontairement petite. Claude ajoute ce dont il a besoin
de trois façons :

| Besoin | Moyen | Durée de vie |
|---|---|---|
| Langage ou outil (Node, Python, Go, Java, Ruby…) | `mise use node@22`, sans root. Les `.nvmrc`, `.tool-versions` et `mise.toml` du projet sont lus : `mise install` | volume `claude-tools`, partagé entre les projets |
| Paquet système dont le projet a toujours besoin | une ligne dans `.claude-docker/packages` du projet (un paquet `apt` par ligne, `#` pour commenter) | image dérivée, reconstruite quand la liste change ; pris en compte au lancement suivant |
| Essai ponctuel | `sudo apt-get install …` | jusqu'à la sortie du conteneur |

`sudo` est sans mot de passe. Les capacités Linux sont réduites à celles
qu'utilisent `sudo` et `apt` (pas de `ping` ni de sockets bruts, par exemple).

`claude-docker --no-sudo` lance une session sans `sudo` ni aucune capacité
(`no-new-privileges`) : `mise` et les paquets du projet restent disponibles.
À utiliser quand Claude tourne sans surveillance.

Chaque version de la liste donne une image `claude-code-pkg:<empreinte>` ;
les anciennes restent sur le disque. `claude-docker --clean` les supprime
toutes : celle du projet est reconstruite à son prochain lancement.

Sous Windows natif, `.claude-docker/packages` et `--clean` ne sont pas pris
en charge.


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

`ssh/` est monté en lecture seule : les empreintes des hôtes sont retenues
dans le volume de config (`~/.claude/ssh_known_hosts`). Si ton `ssh/config`
date d'avant ce changement, supprime-le et relance le script (la clé est
conservée).

Pour signer les commits de Claude à ton nom ou à un nom dédié, renseigne les
variables `GIT_AUTHOR_*` / `GIT_COMMITTER_*` dans `.env`.

### Push

Un hook (`config/managed/hooks/push-guard.sh`) examine chaque commande que
Claude lance. Pour un `git push` ou un merge de PR, Claude Code te demande
ton accord dans le terminal, quel que soit le mode de permission. En mode non
interactif (`-p`), où personne ne peut répondre, le push est refusé.

Deux cas passent sans demander :

- les repos d'agents de `CLAUDE_AGENTS_PUSH` (voir plus bas) ;
- les couples repo:branche de `CLAUDE_PUSH_ALLOW`, dans `.env` :
  ```
  CLAUDE_PUSH_ALLOW=api:claude/*,front:claude/*
  ```
  Le nom du repo est celui de son remote `origin`, sans `.git`.

Même dans ces cas, le hook demande ton accord pour un `--force`, une
suppression de branche, un push de tags, un refspec `a:b` ou un remote donné
par URL. Les réglages sont dans `.env` et dans un dossier monté en lecture
seule : Claude ne peut pas s'accorder lui-même une exception.

Un second filet couvre les push que le hook ne voit pas, ceux lancés par un
script, un `Makefile` ou un outil : dans le conteneur, `/usr/bin/git` est
remplacé par un relais vers une enveloppe (`config/managed/bin/git`) qui
applique la même règle, y compris pour `sudo git` ou un chemin absolu. Un push
hors exception y est refusé, sauf pendant la commande pour laquelle tu
viens de donner ton accord. Conséquence : un `!git push` tapé par toi dans
Claude est refusé lui aussi ; demande-le à Claude ou pousse depuis ta
machine.

Ce qui reste hors de portée : le vrai binaire existe toujours dans l'image
(`/usr/lib/git-core/git`), et un programme peut parler à la forge sans
`git`. Claude ne peut pas l'appeler directement sans que le hook te demande
ton accord, mais un script écrit exprès pour ça passerait. Aucun contrôle
fait dans le conteneur ne peut l'empêcher, puisque la clé SSH y est lisible.
La garantie forte est côté forge : une clé sans droit d'écriture (deploy key
en lecture seule), ou une protection de branche sur les branches à garder.

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

1. Crée un repo sur ta forge (ex. `claude-agents`), vide ou non.
2. Donne à la clé SSH de Claude l'accès à chaque repo : **en écriture** pour
   ceux où Claude doit publier, en lecture pour les autres.
3. Dans `.env`, sans espaces ni guillemets :
   ```
   CLAUDE_AGENTS_REPOS=perso=../claude-agents,equipe=git@github.com:<equipe>/agents.git
   CLAUDE_AGENTS_PUSH=perso
   ```
   - `CLAUDE_AGENTS_REPOS` : liste `nom=source`, l'ordre donne la priorité
     quand un projet existe dans plusieurs repos. La source est :
     - une **URL git** : Claude le clone dans le conteneur
       (`~/.claude/agents-repos/<nom>`), en ne téléchargeant que les
       projets utilisés ;
     - un **chemin local** (relatif à ce repo, ou absolu) : ta propre copie
       de travail, montée dans le conteneur au même chemin. Tu vois et
       modifies les agents directement, Claude commite et pousse depuis
       elle (seulement ses fichiers, jamais tes modifications en cours).
   - `CLAUDE_AGENTS_PUSH` : les repos où Claude écrit et pousse librement ;
     les autres sont en lecture seule.
   - `CLAUDE_AGENTS_CHECK_HOURS` (optionnel, défaut 24) : délai entre deux
     vérifications de mises à jour.
4. Relance claude-docker.

À chaque lancement, avant le démarrage de Claude, un script
(`config/managed/agents-sync.sh`) :

- **clone** les repos donnés par URL qui ne le sont pas encore ;
- **récupère les mises à jour** de chaque repo d'agents si la dernière
  vérification date de plus de `CLAUDE_AGENTS_CHECK_HOURS` heures. Une copie
  de travail locale qui a des modifications en cours n'est jamais touchée ;
- **lie les agents manquants** : pour chaque repo git du projet lancé qui
  n'a pas encore d'agent, il cherche dans les repos d'agents et le lie ;
- **transmet à Claude** ce qu'il a fait et le `CLAUDE.md` du projet, par un
  hook de début de session.

Claude te résume en une ou deux lignes ce qui est nouveau, et ne dit rien
sinon. Ce travail ne consomme plus de tokens et ne dépend plus du modèle.

Fonctionnement :

- Claude **pousse librement** sur les repos de `CLAUDE_AGENTS_PUSH` (branche
  par défaut, sans `--force`) ; c'est la seule exception automatique à la
  règle « pas de push sans accord ». Les nouveaux projets vont dans le
  premier de cette liste. Un projet d'un repo en lecture seule n'est pas
  modifié : Claude propose de le copier dans un repo inscriptible.
- Les agents récupérés sont liés dans `~/.claude/agents/` et deviennent
  disponibles dans tous les projets. Ceux que le script lie au lancement
  le sont dès cette session.

Exemples de demandes :
> Récupère les agents de ma-plateforme.
> Récupère seulement l'agent api de ma-plateforme dans equipe.
> Quels projets sont disponibles dans mes repos d'agents ?

Pour modifier les règles, édite `config/CLAUDE.md` ; c'est pris en compte au
lancement suivant, sans reconstruire l'image.

## Structure

```
bin/claude-docker         script de lancement (bash)
bin/claude-docker.ps1     script de lancement (PowerShell, Windows)
fish/claude-docker.fish   fonction fish
install-fish.sh           installation de la fonction fish
bash/claude-docker.bash   fonction bash
install-bash.sh           installation de la fonction bash
setup-ssh-key.sh          création de la clé SSH dédiée à Claude
config/CLAUDE.md          règles globales montées dans le conteneur
config/managed/           réglages imposés, hooks et scripts de démarrage
                          (start.sh, agents-sync.sh), montés dans /etc/claude-code
dockerfile                image Claude Code (Debian + installeur natif)
.env.template             variables attendues dans .env
tests/                    tests des scripts (lancés par la CI, .github/workflows/ci.yml)
scripts/update-versions.sh  met à jour les versions fixées dans le dockerfile
```

## Tests

```bash
tests/push-guard.test.sh     # hook de contrôle des push (git, jq)
tests/git-wrapper.test.sh    # enveloppe de git, lancé dans le conteneur par docker.test.sh
tests/agents-sync.test.sh    # synchronisation des repos d'agents (git)
tests/docker.test.sh         # build de l'image et lancement (Docker)
```

La CI GitHub Actions les lance à chaque push, avec `shellcheck` et une
vérification de syntaxe du script PowerShell. Le script PowerShell n'est pas
exécuté par la CI.

## Changements

Voir [CHANGELOG.md](CHANGELOG.md), à lire après un `git pull`.

## Licence

[MIT](LICENSE).
