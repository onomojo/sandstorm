#!/bin/bash
set -e

echo "=== Sandstorm: Starting up ==="

# -------------------------------------------------------------------
# 1. Configure git identity (required — passed from host)
# -------------------------------------------------------------------
if [ -z "$GIT_USER_NAME" ] || [ -z "$GIT_USER_EMAIL" ]; then
  echo "ERROR: GIT_USER_NAME and GIT_USER_EMAIL must be set."
  exit 1
fi

git config --global user.name "$GIT_USER_NAME"
git config --global user.email "$GIT_USER_EMAIL"

mkdir -p /home/claude
cat > /home/claude/.gitconfig << GITEOF
[user]
    name = ${GIT_USER_NAME}
    email = ${GIT_USER_EMAIL}
GITEOF
chown claude:claude /home/claude/.gitconfig

# -------------------------------------------------------------------
# 2. Clone the repository
# -------------------------------------------------------------------
if [ -z "$GIT_REPO" ]; then
  echo "ERROR: GIT_REPO must be set (e.g., 'myorg/myrepo')."
  exit 1
fi

if [ ! -d "/app/.git" ]; then
  echo "Cloning ${GIT_REPO}..."
  if [ -n "${GITHUB_TOKEN_READONLY:-}" ]; then
    git clone "https://${GITHUB_TOKEN_READONLY}@github.com/${GIT_REPO}.git" /tmp/repo
  else
    git clone "https://github.com/${GIT_REPO}.git" /tmp/repo
  fi
  # Move into /app (which may have empty dirs from volume subpath mounts)
  cp -a /tmp/repo/. /app/
  rm -rf /tmp/repo
  cd /app
  git remote set-url origin "https://github.com/${GIT_REPO}.git"
else
  echo "Repository already cloned, pulling latest..."
  cd /app
  git pull || true
fi

# -------------------------------------------------------------------
# 3. Checkout branch if specified
# -------------------------------------------------------------------
if [ -n "$GIT_BRANCH" ]; then
  echo "Checking out branch: $GIT_BRANCH"
  git checkout "$GIT_BRANCH" || git checkout -b "$GIT_BRANCH"
fi

# -------------------------------------------------------------------
# 4. Set up .env from sample if one doesn't exist
# -------------------------------------------------------------------
cd /app
if [ ! -f ".env" ]; then
  for sample in .sample.env .env.sample .env.example; do
    if [ -f "$sample" ]; then
      echo "Creating .env from ${sample}..."
      cp "$sample" .env
      # Override DB/Redis to point at compose services
      sed -i "s|^DATABASE_HOST=.*|DATABASE_HOST=${PGHOST:-postgres}|" .env 2>/dev/null || true
      sed -i "s|^DATABASE_PASSWORD=.*|DATABASE_PASSWORD=${PGPASSWORD:-password}|" .env 2>/dev/null || true
      sed -i "s|^DATABASE_USERNAME=.*|DATABASE_USERNAME=${PGUSER:-postgres}|" .env 2>/dev/null || true
      sed -i "s|^REDIS_URL=.*|REDIS_URL=${REDIS_URL:-redis://redis:6379/0}|" .env 2>/dev/null || true
      break
    fi
  done
fi

# -------------------------------------------------------------------
# 5. Set ownership and signal readiness
# -------------------------------------------------------------------
chown -R claude:claude /app
chown -R claude:claude /home/claude
chown -R claude:claude /usr/local/bundle 2>/dev/null || true

# Copy sandstorm inner instructions into the workspace
if [ -f /usr/bin/SANDSTORM_INNER.md ]; then
  # Append to existing CLAUDE.md or create one
  if [ -f /app/CLAUDE.md ]; then
    echo "" >> /app/CLAUDE.md
    cat /usr/bin/SANDSTORM_INNER.md >> /app/CLAUDE.md
  else
    cp /usr/bin/SANDSTORM_INNER.md /app/CLAUDE.md
  fi
fi

# Fix docker socket permissions so claude user can access it
if [ -S /var/run/docker.sock ]; then
  chmod 666 /var/run/docker.sock
fi

# Signal to other services that the repo is ready
touch /app/.sandstorm-ready

echo ""
echo "=========================================="
echo "  Sandstorm Claude workspace is READY"
echo "=========================================="
echo "  Repo:  ${GIT_REPO}"
echo "=========================================="
echo ""

# -------------------------------------------------------------------
# 6. Start task runner (PID 1 — output goes to docker logs)
# -------------------------------------------------------------------
exec gosu claude /usr/bin/sandstorm-task-runner.sh
