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
        unzip \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Utilisateur non-root (UID/GID ajustables pour coller à ceux de l'hôte)
ARG USERNAME=dev
ARG UID=1000
ARG GID=1000
RUN (getent group ${GID} >/dev/null || groupadd -g ${GID} ${USERNAME}) \
    && useradd -m -u ${UID} -g ${GID} -s /bin/bash ${USERNAME} \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

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

# mise : langages et outils installés sans root, conservés dans un volume
ENV MISE_DATA_DIR=${HOME}/.local/share/mise
ENV MISE_GLOBAL_CONFIG_FILE=${MISE_DATA_DIR}/config.toml \
    MISE_TRUSTED_CONFIG_PATHS=/ \
    MISE_YES=1 \
    MISE_IDIOMATIC_VERSION_FILE_ENABLE_TOOLS=node,python,ruby,go,java \
    PATH=${MISE_DATA_DIR}/shims:${PATH}
RUN curl -fsSL https://mise.run | sh && mkdir -p ${MISE_DATA_DIR}

WORKDIR /workspace

CMD ["claude"]
