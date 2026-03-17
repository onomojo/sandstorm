# Sandstorm

Docker-based harness for running Claude Code in isolated containers. Sandstorm layers Claude tooling alongside your project's existing Docker setup, enabling parallel autonomous code execution across multiple stacks.

## Prerequisites

- [Docker](https://www.docker.com/) running locally
- [Claude Code](https://claude.ai/claude-code) installed (`claude` CLI)
- [GitHub CLI](https://cli.github.com/) authenticated (`gh auth login`)
- A **GitHub Personal Access Token (read-only)** for cloning your repo inside containers

### Creating the GitHub Token

Each Sandstorm stack clones your repo into an isolated workspace. This requires a read-only GitHub PAT:

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

### 3. Initialize Your Project

```bash
cd ~/Work/myproject
sandstorm init
```

This reads your existing `docker-compose.yml` and generates:
- `.sandstorm/config` — project settings, GitHub token, port mappings
- `.sandstorm/docker-compose.yml` — override that adds a Claude workspace container and remaps ports

Then add your read-only GitHub token to `.sandstorm/config`:

```bash
# Edit .sandstorm/config and set:
GITHUB_TOKEN_READONLY=github_pat_YOUR_TOKEN_HERE
```

### 4. Run Sandstorm

```bash
sandstorm up 1
```

This clones your repo into an isolated workspace, starts all your project services (postgres, redis, api, frontend, etc.), and adds a dedicated Claude container alongside them. All services run exactly as they would in normal dev — bind mounts resolve to the cloned workspace, your entrypoints and setup scripts work as-is.

```bash
sandstorm          # Launch outer Claude (interactive orchestrator)
sandstorm status   # Check stack status
```

## How It Works

Sandstorm creates isolated Docker environments by:

1. **Cloning** your repo to `.sandstorm/workspaces/<stack_id>/` on the host
2. **Running** your project's docker-compose.yml from the workspace directory (bind mounts resolve to the clone, not your working copy)
3. **Overlaying** a sandstorm compose that adds a Claude workspace container and remaps host ports
4. **Each stack** gets its own database, Redis, services, and repo clone — fully isolated

The Claude container sits on the same Docker network as your services and can communicate with everything by hostname (db, redis, api, etc.). It runs in `--dangerously-skip-permissions` mode for autonomous operation but has **no GitHub write access** — only the read-only clone token. Push operations happen from the host via `sandstorm push`.

### Port Remapping

Each stack's host ports are offset by `stack_id * PORT_OFFSET` (default: 10) to avoid conflicts:

| Service | Original | Stack 1 | Stack 2 |
|---------|----------|---------|---------|
| api     | 3001     | 3011    | 3021    |
| app     | 3002     | 3012    | 3022    |
| db      | 5433     | 5443    | 5453    |

The offset is configurable in `.sandstorm/config` via `PORT_OFFSET`.

## Usage

### Spin up a stack and dispatch a task

```bash
sandstorm up 1
sandstorm task 1 "Fix the login bug. Write tests. Run linters."
sandstorm task-status 1
sandstorm diff 1
sandstorm publish 1 fix/login-bug "Fix login validation"
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
| `sandstorm init` | Initialize Sandstorm in a project |
| `sandstorm up <id> [--ticket T] [--branch B]` | Start a new stack |
| `sandstorm down <id>` | Tear down stack and clean up workspace |
| `sandstorm task <id> "prompt"` | Dispatch task (async) |
| `sandstorm task <id> --sync "prompt"` | Dispatch task (sync) |
| `sandstorm task <id> --file path` | Dispatch task from file |
| `sandstorm task-status <id>` | Check task status |
| `sandstorm task-output <id> [lines]` | Show task output |
| `sandstorm diff <id>` | Git diff inside container |
| `sandstorm push <id> ["msg"]` | Commit and push |
| `sandstorm publish <id> <branch> ["msg"]` | Create branch and push |
| `sandstorm exec <id>` | Shell into the Claude container |
| `sandstorm claude <id>` | Run inner Claude interactively |
| `sandstorm status` | Dashboard of all stacks |
| `sandstorm logs <id> [service]` | Tail container logs (default: claude) |

## Project Setup

### What `sandstorm init` does

1. Reads your existing `docker-compose.yml`
2. Extracts port mappings for each service
3. Generates `.sandstorm/config` with project name, port map, and settings
4. Generates `.sandstorm/docker-compose.yml` override that adds a Claude container and remaps ports
5. Updates `.gitignore` to exclude sandstorm workspaces and config (which contains tokens)

### What your project needs

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Your services (postgres, redis, api, frontend, etc.) |
| `Dockerfile` / `Dockerfile.dev` | Your dev environment for each service |
| `CLAUDE.md` | Coding standards for the inner Claude |
| Entrypoints that handle fresh starts | `bundle install` if gems missing, `npm install` if node_modules missing, `db:prepare` on empty DB |

**Important:** Sandstorm creates fresh Docker volumes for each stack. Your project's entrypoints should handle first-run setup (dependency installation, database migrations, seeding) so stacks boot automatically.

### Environment files

When `sandstorm up` clones the workspace, it automatically copies all `.env*` files from your project root into the workspace (`.env`, `.env.local`, `.env.development`, etc.). These are typically gitignored but required for services to run. If your project has env files in subdirectories, you may need to copy those manually or add a `.sandstorm/setup.sh` hook.

### What Sandstorm provides

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Outer Claude orchestration instructions |
| `docker/Dockerfile` | Lightweight Claude workspace (git, Claude CLI, GitHub CLI) |
| `docker/entrypoint.sh` | Sets up git identity, signals readiness |
| `lib/init.sh` | Project initialization |
| `lib/stack.sh` | Stack management CLI |

### Credential flow

| Credential | Where it lives | Used for |
|------------|---------------|----------|
| `GITHUB_TOKEN_READONLY` | `.sandstorm/config` | Cloning repo into workspace |
| `gh auth` token | Host (via `gh auth login`) | Push/publish operations |
| Claude OAuth | Host (auto-synced from Claude Code session) | Inner Claude authentication |

- The **read-only token** is used once during `sandstorm up` to clone the repo. It's stored in the workspace's `.git/config` remote URL — the Claude container has read-only access only.
- **Push operations** inject the host's `gh auth` token only during `sandstorm push/publish` — it's never stored in the container.
- Inner Claude runs in **dangerous mode** but cannot write to GitHub.

## Architecture

```
You (developer)
  └── sandstorm (outer Claude — orchestrator)
        ├── Stack 1 (sandstorm-myproject-1)
        │     ├── claude (workspace — edits code, runs tests)
        │     ├── api, frontend, etc. (your services — unchanged)
        │     └── postgres, redis, etc. (infrastructure)
        ├── Stack 2 (sandstorm-myproject-2)
        │     └── ... (fully independent clone)
        └── Stack 3 ...
```

- **Outer Claude** reads Sandstorm's CLAUDE.md. Plans, researches, orchestrates.
- **Inner Claude** reads your project's CLAUDE.md. Writes code, runs tests, runs linters.
- **Each stack is fully isolated.** Own workspace clone, own database, own Redis, own ports.
- **Project services run untouched.** Same Dockerfiles, entrypoints, and commands as normal dev.

### Stack naming

Stacks are named `sandstorm-<project>-<id>` using the project directory name. This allows multiple projects to run sandstorm stacks simultaneously without conflicts.

## Configuration

`.sandstorm/config` settings:

| Setting | Default | Description |
|---------|---------|-------------|
| `PROJECT_NAME` | directory name | Used in stack naming |
| `COMPOSE_FILE` | `docker-compose.yml` | Project compose file |
| `PORT_MAP` | auto-detected | Service port mappings |
| `PORT_OFFSET` | `10` | Port offset multiplier per stack |
| `GITHUB_TOKEN_READONLY` | — | Read-only PAT for cloning |
| `TICKET_PREFIX` | — | Ticket prefix for push safety checks |
| `PROTECTED_FILES` | `CLAUDE.md` | Files restored before push |

## License

MIT
