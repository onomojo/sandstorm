# Sandstorm

Docker-based harness for running Claude Code in isolated containers. Sandstorm layers Claude tooling onto your project's existing Docker setup, enabling parallel autonomous code execution across multiple stacks.

## Prerequisites

- [Docker](https://www.docker.com/) running locally
- [Claude Code](https://claude.ai/claude-code) installed (`claude` CLI)
- [GitHub CLI](https://cli.github.com/) authenticated (`gh auth login`)
- A **GitHub Personal Access Token (read-only)** for cloning your repo inside containers

### Creating the GitHub Token

Each Sandstorm stack clones your repo inside an isolated container. This requires a read-only GitHub PAT:

1. Go to https://github.com/settings/personal-access-tokens/new
2. **Token name:** `sandstorm-readonly`
3. **Expiration:** 90 days (or your preference)
4. **Repository access:** "Only select repositories" — pick the repo(s) you'll use with Sandstorm
5. **Permissions:** Repository permissions → **Contents: Read-only** (nothing else needed)
6. Click **Generate token** and copy it

**Note:** If your repo is in an organization, the org admin may need to approve the token before it works.

## Quick Start

### 1. Clone Sandstorm

```bash
git clone git@github.com:onomojo/sandstorm.git ~/Work/sandstorm
```

### 2. Add to PATH

```bash
# Add to ~/.zshrc or ~/.bashrc
export PATH="$HOME/Work/sandstorm/bin:$PATH"
```

### 3. Configure Your Project

Create a `.sandstorm/config` file in your project:

```bash
mkdir -p .sandstorm

cat > .sandstorm/config << 'EOF'
# Required: which docker-compose service to run Claude in
SERVICE=web

# Required: read-only GitHub PAT for cloning inside containers
GITHUB_TOKEN_READONLY=github_pat_YOUR_TOKEN_HERE

# Optional: ticket prefix for push safety checks (e.g., PROJ, JIRA)
# TICKET_PREFIX=PROJ

# Optional: base port numbers (stack ID is added: stack 1 = 3001, stack 2 = 3002)
# APP_PORT_BASE=3000
# CHROME_PORT_BASE=9300

# Optional: files to restore after inner Claude finishes (prevents contamination)
# PROTECTED_FILES=CLAUDE.md
EOF
```

Then add it to your `.gitignore`:

```bash
echo ".sandstorm/" >> .gitignore
```

Your project also needs:
- A `docker-compose.yml` with the service named in `SERVICE`
- A `Dockerfile` referenced by that service

### 4. Run Sandstorm

```bash
cd ~/Work/myproject
sandstorm
```

This launches Claude Code with Sandstorm's orchestration instructions. You're now the outer Claude — you plan and orchestrate, while inner Claudes execute code inside isolated containers.

## How It Works

Sandstorm creates isolated Docker environments by:
1. Building your project's Docker image (from your existing Dockerfile)
2. Layering Claude Code CLI, GitHub CLI, and tooling on top
3. Starting your full stack (postgres, redis, etc.) in an isolated compose project
4. Cloning your repo inside the container
5. Running an inner Claude that follows your project's `CLAUDE.md`

Each stack is fully isolated — its own database, Redis, and services. You can run multiple stacks in parallel.

## Usage

### Spin up a stack and dispatch a task

```bash
sandstorm up 1
sandstorm task 1 "Checkout branch main. Add email validation to the User model. Write tests. Run linters."
sandstorm task-status 1
sandstorm diff 1
sandstorm push 1 "Add email validation"
sandstorm down 1
```

### Parallel work

```bash
sandstorm up 1 --ticket PROJ-100
sandstorm up 2 --ticket PROJ-101
sandstorm up 3 --ticket PROJ-102
sandstorm task 1 --ticket PROJ-100 "Fix the login bug..."
sandstorm task 2 --ticket PROJ-101 "Add search feature..."
sandstorm task 3 --ticket PROJ-102 "Refactor payment service..."
sandstorm status
```

### Interactive inner Claude

```bash
sandstorm claude 1    # Drop into inner Claude interactively
sandstorm exec 1      # Shell into the container
```

## Commands

| Command | Description |
|---------|-------------|
| `sandstorm` | Launch outer Claude (interactive orchestrator) |
| `sandstorm up <id> [--ticket T]` | Start a new stack |
| `sandstorm down <id>` | Tear down stack |
| `sandstorm task <id> "prompt"` | Dispatch task (async) |
| `sandstorm task <id> --sync "prompt"` | Dispatch task (sync) |
| `sandstorm task <id> --file path` | Dispatch task from file |
| `sandstorm task-status <id>` | Check task status |
| `sandstorm task-output <id> [lines]` | Show task output |
| `sandstorm diff <id>` | Git diff inside container |
| `sandstorm push <id> ["msg"]` | Commit and push |
| `sandstorm publish <id> <branch> ["msg"]` | Create branch and push |
| `sandstorm exec <id>` | Shell into container |
| `sandstorm claude <id>` | Run inner Claude interactively |
| `sandstorm status` | Dashboard of all stacks |
| `sandstorm logs <id>` | Tail container logs |

## Project Setup

### What your project provides

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Your services (postgres, redis, web, etc.) |
| `Dockerfile` | Your dev environment (language runtime, dependencies) |
| `CLAUDE.md` | Coding standards for the inner Claude |
| `.sandstorm/config` | Sandstorm config (service, token, ticket prefix) |
| `.claude/settings.json` | MCP servers (Jira, BugSnag, etc.) — optional |
| `.claude/commands/` | Skills (/start-ticket, /create-pr, etc.) — optional |

### What Sandstorm provides

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Outer Claude orchestration instructions |
| `docker/Dockerfile` | Layers Claude CLI onto your project's image |
| `docker/entrypoint.sh` | Clones repo, runs hooks, starts inner Claude |
| `lib/stack.sh` | Stack management CLI |

### Credential flow

| Credential | Where it lives | Used for |
|------------|---------------|----------|
| `GITHUB_TOKEN_READONLY` | `.sandstorm/config` | Cloning repo inside containers |
| `gh auth` token | Host (via `gh auth login`) | Push/publish operations |
| Claude OAuth | Host (auto-synced from Claude Code session) | Inner Claude authentication |

Push operations inject the host's `gh auth` token only during `sandstorm push/publish` — it's never stored in the container.

## Architecture

```
You (developer)
  └── sandstorm (outer Claude — orchestrator)
        ├── Stack 1 (inner Claude — executes code)
        │     ├── postgres, redis, etc.
        │     └── your app (cloned repo)
        ├── Stack 2 (inner Claude — executes code)
        │     ├── postgres, redis, etc.
        │     └── your app (cloned repo)
        └── Stack 3 ...
```

- **Outer Claude** reads Sandstorm's CLAUDE.md. Plans, researches, orchestrates.
- **Inner Claude** reads your project's CLAUDE.md. Writes code, runs tests, runs linters.
- **Each stack is fully isolated.** Own database, own Redis, own repo clone.

## License

MIT
