# Claude Code CLI dans un conteneur générique
FROM debian:bookworm-slim

# Versions installées. Pour mettre à jour : change-les ici, l'image est
# reconstruite au lancement suivant. Empreintes de mise : SHASUMS256.txt de
# la release, https://github.com/jdx/mise/releases
ARG CLAUDE_VERSION=2.1.332
ARG MISE_VERSION=v2026.11.14
ARG MISE_SHA256_AMD64=6fa596291e9758106f761fea4f8e7fac6c3e7ff4714d5c0b9a76e16068db14f6
ARG MISE_SHA256_ARM64=7bd3b2d5ffff077a7662ba186c09600e5b40c1eee9df0c264ed67642ce0a8698

# Outils de base utiles à Claude Code (git, recherche, réseau)
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        jq \
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

# La version de Claude Code est fixée par CLAUDE_VERSION
ENV DISABLE_AUTOUPDATER=1

# Installeur natif officiel, à la version fixée
RUN curl -fsSL https://claude.ai/install.sh | bash -s -- "${CLAUDE_VERSION}"

# mise : langages et outils installés sans root, conservés dans un volume
ENV MISE_DATA_DIR=${HOME}/.local/share/mise
ENV MISE_GLOBAL_CONFIG_FILE=${MISE_DATA_DIR}/config.toml \
    MISE_TRUSTED_CONFIG_PATHS=/ \
    MISE_YES=1 \
    MISE_IDIOMATIC_VERSION_FILE_ENABLE_TOOLS=node,python,ruby,go,java \
    PATH=${MISE_DATA_DIR}/shims:${PATH}
RUN case "$(dpkg --print-architecture)" in \
        amd64) arch=x64; sum=${MISE_SHA256_AMD64} ;; \
        arm64) arch=arm64; sum=${MISE_SHA256_ARM64} ;; \
        *) echo "architecture non prise en charge pour mise" >&2; exit 1 ;; \
    esac \
    && mkdir -p ${HOME}/.local/bin ${MISE_DATA_DIR} \
    && curl -fsSL -o ${HOME}/.local/bin/mise \
        "https://github.com/jdx/mise/releases/download/${MISE_VERSION}/mise-${MISE_VERSION}-linux-${arch}" \
    && echo "${sum}  ${HOME}/.local/bin/mise" | sha256sum -c - \
    && chmod +x ${HOME}/.local/bin/mise

WORKDIR /workspace

CMD ["claude"]
