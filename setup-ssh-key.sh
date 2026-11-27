#!/usr/bin/env bash
# Crée une clé SSH dédiée à Claude, montée dans le conteneur comme ~/.ssh.
# La clé reste dans ssh/ (ignoré par git) : ta propre clé n'est jamais exposée.
# Relançable sans risque : une clé existante n'est pas écrasée.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
SSH_DIR="$REPO_DIR/ssh"
KEY="$SSH_DIR/id_ed25519"

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [[ -f "$KEY" ]]; then
    echo "Clé déjà présente : $KEY"
else
    # Sans passphrase : Claude ne peut pas la saisir. Limite donc les droits
    # de cette clé côté forge (voir README).
    ssh-keygen -t ed25519 -N "" -C "claude-docker@$(hostname)" -f "$KEY" >/dev/null
    echo "Clé créée : $KEY"
fi

if [[ ! -f "$SSH_DIR/config" ]]; then
    cat > "$SSH_DIR/config" <<'CONF'
Host *
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    # Accepte l'empreinte d'un hôte inconnu à la première connexion,
    # refuse ensuite tout changement. ~/.ssh est en lecture seule : les
    # empreintes vont dans le volume de config.
    StrictHostKeyChecking accept-new
    UserKnownHostsFile ~/.claude/ssh_known_hosts ~/.ssh/known_hosts
CONF
fi
touch "$SSH_DIR/known_hosts"
chmod 600 "$KEY" "$SSH_DIR/config" "$SSH_DIR/known_hosts"

cat <<EOF

Clé publique à ajouter sur ta forge (GitHub, GitLab…) :

$(cat "$KEY.pub")

  - Deploy key d'un repo (recommandé) : Settings → Deploy keys,
    sans cocher « Allow write access » si Claude n'a pas à pousser.
  - Ou clé de compte : Settings → SSH and GPG keys (accès à tous tes repos).

Elle sera montée dans le conteneur au prochain lancement de claude-docker.
Test depuis le conteneur : ssh -T git@github.com
EOF
