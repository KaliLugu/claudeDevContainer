# Claude Code CLI dans un conteneur générique
FROM debian:bookworm-slim

# Outils de base utiles à Claude Code (git, recherche, réseau)
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        openssh-client \
        ripgrep \
        less \
        procps \
        sudo \
    && rm -rf /var/lib/apt/lists/*

# Utilisateur non-root (UID/GID ajustables pour coller à ceux de l'hôte)
ARG USERNAME=dev
ARG UID=1000
ARG GID=1000
RUN (getent group ${GID} >/dev/null || groupadd -g ${GID} ${USERNAME}) \
    && useradd -m -u ${UID} -g ${GID} -s /bin/bash ${USERNAME}

USER ${USERNAME}
ENV HOME=/home/${USERNAME}
ENV PATH=${HOME}/.local/bin:${PATH}

# Toute la config Claude (session, réglages, historique) dans un seul dossier,
# à monter en volume pour la conserver entre les lancements
ENV CLAUDE_CONFIG_DIR=${HOME}/.claude
RUN mkdir -p ${CLAUDE_CONFIG_DIR}

# Mise à jour par claude-docker --rebuild
ENV DISABLE_AUTOUPDATER=1

# Installeur natif officiel
RUN curl -fsSL https://claude.ai/install.sh | bash

WORKDIR /workspace

CMD ["claude"]
