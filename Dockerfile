# syntax=docker/dockerfile:1

# Layer order runs from least to most frequently changed, so day-to-day edits to the launcher
# scripts rebuild only the last layers. Tools that are downloaded rather than installed from apt
# are fetched in separate stages: they build in parallel, cache independently, and leave their
# build-time dependencies behind. "Latest" downloads stay cached until you build with --no-cache
# or change the matching --build-arg.

ARG UBUNTU_VERSION=26.04

# ---- fetch stage: minimal image with just what the download stages need ----
FROM ubuntu:${UBUNTU_VERSION} AS fetch
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl jq unzip xz-utils \
 && rm -rf /var/lib/apt/lists/*

FROM fetch AS node
ARG NODE_MAJOR=24
RUN set -eux; \
    case "$(dpkg --print-architecture)" in amd64) arch=x64 ;; arm64) arch=arm64 ;; esac; \
    ver=$(curl -fsSL https://nodejs.org/dist/index.json | jq -r --arg m "v${NODE_MAJOR}." '[.[] | select(.version | startswith($m))][0].version'); \
    mkdir /out; \
    curl -fsSL "https://nodejs.org/dist/${ver}/node-${ver}-linux-${arch}.tar.xz" \
      | tar -xJ -C /out --strip-components=1 --exclude=CHANGELOG.md --exclude=LICENSE --exclude=README.md

FROM fetch AS kubectl
RUN set -eux; mkdir /out; \
    curl -fsSL "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/$(dpkg --print-architecture)/kubectl" -o /out/kubectl; \
    chmod +x /out/kubectl

FROM fetch AS helm
RUN set -eux; mkdir /out; \
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | PATH="/out:$PATH" USE_SUDO=false HELM_INSTALL_DIR=/out bash

FROM fetch AS talosctl
RUN set -eux; mkdir /out; \
    curl -fsSL https://talos.dev/install | sh; \
    cp /usr/local/bin/talosctl /out/talosctl

FROM fetch AS flux
RUN set -eux; mkdir /out; \
    curl -fsSL https://fluxcd.io/install.sh | bash; \
    cp /usr/local/bin/flux /out/flux

FROM fetch AS vault
RUN set -eux; mkdir /out; \
    arch=$(dpkg --print-architecture); \
    ver=$(curl -fsSL https://checkpoint-api.hashicorp.com/v1/check/vault | jq -r .current_version); \
    curl -fsSL "https://releases.hashicorp.com/vault/${ver}/vault_${ver}_linux_${arch}.zip" -o /tmp/vault.zip; \
    unzip -q /tmp/vault.zip vault -d /out

FROM fetch AS go
RUN set -eux; \
    ver=$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -1); \
    mkdir /out; \
    curl -fsSL "https://go.dev/dl/${ver}.linux-$(dpkg --print-architecture).tar.gz" | tar -xz -C /out --strip-components=1

FROM fetch AS rust
ENV RUSTUP_HOME=/out/rustup CARGO_HOME=/out/cargo
RUN set -eux; \
    curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable -c clippy -c rustfmt --no-modify-path

FROM fetch AS dotnet
ARG DOTNET_CHANNELS="8.0 9.0 10.0"
RUN set -eux; \
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh; \
    for channel in $DOTNET_CHANNELS; do \
      bash /tmp/dotnet-install.sh --channel "$channel" --install-dir /out; \
    done

# Claude Code needs node to install; only its output is carried forward.
FROM fetch AS claude-code
COPY --from=node /out/ /usr/local/
ARG CLAUDE_CODE_VERSION=latest
RUN npm install -g --prefix /opt/claude "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}"

FROM fetch AS typescript
COPY --from=node /out/ /usr/local/
RUN npm install -g --prefix /opt/ts typescript

FROM fetch AS codex
COPY --from=node /out/ /usr/local/
ARG CODEX_VERSION=latest
RUN npm install -g --prefix /opt/codex "@openai/codex@${CODEX_VERSION}"

# ---- final image ----
FROM ubuntu:${UBUNTU_VERSION}

ENV DEBIAN_FRONTEND=noninteractive \
    DISABLE_AUTOUPDATER=1 \
    DOTNET_ROOT=/usr/share/dotnet \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    TZ=Australia/Brisbane \
    LANG=en_AU.UTF-8 \
    RUSTUP_HOME=/opt/rust/rustup \
    CARGO_HOME=/opt/rust/cargo \
    PATH=/opt/launcher/bin:/usr/share/dotnet:/usr/local/go/bin:/opt/rust/cargo/bin:$PATH

# System packages plus the GitHub, Docker and Microsoft apt repos (armored keys, so no gnupg).
# libicu is named per Ubuntu release, so it is looked up rather than hard-coded.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl; \
    install -d -m 0755 /etc/apt/keyrings; \
    arch=$(dpkg --print-architecture); \
    codename=$(. /etc/os-release && echo "$VERSION_CODENAME"); \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli.gpg; \
    echo "deb [arch=$arch signed-by=/etc/apt/keyrings/githubcli.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list; \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc; \
    echo "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $codename stable" > /etc/apt/sources.list.d/docker.list; \
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc -o /etc/apt/keyrings/microsoft.asc; \
    echo "deb [arch=$arch signed-by=/etc/apt/keyrings/microsoft.asc] https://packages.microsoft.com/repos/azure-cli/ $codename main" > /etc/apt/sources.list.d/azure-cli.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      tzdata locales gcc libc6-dev make git openssh-client openssl bind9-dnsutils tmux sudo jq ripgrep unzip less procps python3 python3-pip ttyd \
      gh docker-ce-cli docker-buildx-plugin docker-compose-plugin azure-cli \
      $(apt-cache search --names-only '^libicu[0-9]+$' | cut -d' ' -f1); \
    locale-gen en_AU.UTF-8; \
    rm -rf /var/lib/apt/lists/*

# Downloaded tools, least to most frequently updated.
COPY --from=node /out/ /usr/local/
COPY --from=dotnet /out/ /usr/share/dotnet/
COPY --from=kubectl /out/kubectl /usr/local/bin/kubectl
COPY --from=helm /out/helm /usr/local/bin/helm
COPY --from=talosctl /out/talosctl /usr/local/bin/talosctl
COPY --from=flux /out/flux /usr/local/bin/flux
COPY --from=vault /out/vault /usr/local/bin/vault
COPY --from=go /out/ /usr/local/go/

# Bypass-permissions mode is refused as root, so run as a normal user.
RUN userdel -r ubuntu 2>/dev/null || true \
 && useradd -m -u 1000 -s /bin/bash claude \
 && echo 'claude ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/claude \
 && mkdir -p /workspace && chown claude:claude /workspace

# Owned by claude so rustup can update toolchains and cargo can cache crates.
COPY --from=rust --chown=claude:claude /out/ /opt/rust/
COPY --from=typescript /opt/ts/ /usr/local/
COPY --from=codex /opt/codex/ /usr/local/
COPY --from=claude-code /opt/claude/ /usr/local/

# Launcher files change most often, so they come last.
COPY bin/ /opt/launcher/bin/
COPY lib/ /opt/launcher/lib/
COPY config/ /opt/launcher/config/
RUN chmod -R u=rwX,go=rX /opt/launcher && chmod 755 /opt/launcher/bin/*

USER claude
WORKDIR /workspace
ENV WORKSPACE=/workspace
EXPOSE 7681
ENTRYPOINT ["/opt/launcher/bin/entrypoint"]
