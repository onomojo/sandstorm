# Sandstorm — layers Claude Code tooling onto any project base image.
#
# Usage:
#   docker build --build-arg BASE_IMAGE=myproject:latest -f /path/to/sandstorm/docker/Dockerfile .

ARG BASE_IMAGE=debian:bookworm-slim
FROM ${BASE_IMAGE}

# Core dependencies (skip if already installed)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    curl \
    gnupg \
    sudo \
    gosu \
    jq \
    openssh-client \
  && rm -rf /var/lib/apt/lists/*

# Node.js (required for Claude CLI — skip if already present)
RUN if ! command -v node >/dev/null 2>&1; then \
      curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
      apt-get install -y nodejs && \
      rm -rf /var/lib/apt/lists/*; \
    fi

# Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# GitHub CLI (skip if already present)
RUN if ! command -v gh >/dev/null 2>&1; then \
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
      apt-get update && apt-get install -y gh && \
      rm -rf /var/lib/apt/lists/*; \
    fi

# Non-root claude user (skip if already exists)
RUN id claude >/dev/null 2>&1 || ( \
      useradd -m -s /bin/bash claude && \
      echo "claude ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
    )

# Hooks directory (project can mount hooks here)
RUN mkdir -p /usr/share/sandstorm/hooks

# Entrypoint
COPY docker/entrypoint.sh /usr/bin/sandstorm-entrypoint.sh
RUN chmod +x /usr/bin/sandstorm-entrypoint.sh

WORKDIR /app

ENTRYPOINT ["/usr/bin/sandstorm-entrypoint.sh"]
CMD ["bash"]
