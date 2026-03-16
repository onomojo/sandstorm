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
  git clone "https://${GITHUB_TOKEN_READONLY}@github.com/${GIT_REPO}.git" /app
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
# 5. Run the project's own entrypoint for setup
#    Sources the shell profile first so Ruby/Node/etc. are on PATH.
#    Passes "true" as $@ so the entrypoint's final "exec $@" is a no-op.
# -------------------------------------------------------------------

# Look for the project's entrypoint in common locations
PROJECT_ENTRYPOINT=""
for candidate in /usr/bin/docker-entrypoint.sh /app/docker-entrypoint.sh; do
  if [ -x "$candidate" ]; then
    PROJECT_ENTRYPOINT="$candidate"
    break
  fi
done

# -------------------------------------------------------------------
# 6. Set ownership before running project setup
# -------------------------------------------------------------------
chown -R claude:claude /app
chown -R claude:claude /home/claude
chown -R claude:claude /usr/local/bundle 2>/dev/null || true

echo ""
echo "=========================================="
echo "  Sandstorm Stack is READY"
echo "=========================================="
echo "  Repo:  ${GIT_REPO}"
echo ""
echo "  To run Claude:"
echo "    claude --dangerously-skip-permissions"
echo "=========================================="
echo ""

# -------------------------------------------------------------------
# 7. Run project entrypoint + app command as claude user
#    APP_COMMAND comes from the project's docker-compose command.
#    If a project entrypoint exists, it does setup (bundle install,
#    db:migrate, etc.) and then exec's into APP_COMMAND.
#    If no project entrypoint, just run APP_COMMAND directly.
# -------------------------------------------------------------------
if [ -n "$PROJECT_ENTRYPOINT" ]; then
  exec gosu claude "$PROJECT_ENTRYPOINT" ${APP_COMMAND:-bash}
elif [ -n "$APP_COMMAND" ]; then
  exec gosu claude $APP_COMMAND
else
  exec gosu claude bash
fi
