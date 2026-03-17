# Sandstorm — Claude Code workspace container.
#
# A lightweight workspace with Claude Code, git, and GitHub CLI.
# Sits alongside project services on the Docker network.

FROM debian:bookworm-slim

# Core dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    curl \
    sudo \
    gosu \
    jq \
    openssh-client \
  && rm -rf /var/lib/apt/lists/*

# Claude Code CLI
RUN curl -fsSL https://claude.ai/install.sh | bash

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && apt-get install -y gh && \
    rm -rf /var/lib/apt/lists/*

# Non-root claude user
RUN useradd -m -s /bin/bash claude && \
    echo "claude ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Entrypoint
COPY docker/entrypoint.sh /usr/bin/sandstorm-entrypoint.sh
RUN chmod +x /usr/bin/sandstorm-entrypoint.sh

WORKDIR /app

ENTRYPOINT ["/usr/bin/sandstorm-entrypoint.sh"]
CMD ["sleep", "infinity"]
