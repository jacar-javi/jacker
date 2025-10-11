# Dev Container Configuration

This directory contains the configuration for VS Code Dev Containers, providing a fully configured development environment for the Jacker project.

## What is a Dev Container?

A Dev Container is a Docker container specifically configured for development. It includes:
- All required tools and dependencies
- VS Code extensions pre-installed
- Environment variables and settings
- Port forwarding for services
- Lifecycle scripts for setup

**Benefits:**
- ✅ Consistent development environment across all contributors
- ✅ No need to install tools locally (Docker, Node.js, BATS, etc.)
- ✅ Isolated from your host system
- ✅ Reproducible builds and testing
- ✅ Quick onboarding for new developers

## Files

### `devcontainer.json`
**Main dev container configuration**

**Features:**
- Base image: Node.js 22 on Debian Bullseye
- Docker-in-Docker for running Jacker services
- Common utilities (Zsh, Oh My Zsh, Git)
- 17 VS Code extensions auto-installed
- Port forwarding for all Jacker services
- Lifecycle scripts (post-create, post-start)
- Non-root user (node) for security

**Extensions Installed:**
- Shell scripting (ShellCheck, Shell Format, Bash IDE)
- Docker (Docker extension, Remote Containers)
- YAML (Schema validation, formatting)
- Markdown (All-in-One, Markdownlint)
- Git (GitLens, Git Graph)
- Testing (BATS support)
- Code quality (EditorConfig, Spell Checker)
- Utilities (TODO Tree, Better Comments, Indent Rainbow)

**Ports Forwarded:**
- 80 - HTTP
- 443 - HTTPS
- 3000 - Grafana
- 8080 - Traefik Dashboard
- 9090 - Prometheus
- 9093 - Alertmanager
- 5432 - PostgreSQL

### `post-create.sh`
**Post-creation setup script**

Runs once after the dev container is created to:
1. Install system dependencies (shellcheck, jq, make, etc.)
2. Install BATS testing framework v1.10.0
3. Configure Docker access
4. Set up Git with helpful aliases
5. Add bash aliases for Jacker commands
6. Create necessary directories
7. Set file permissions
8. Verify all tools are installed

**Installed Tools:**
- ShellCheck - Bash linting
- shfmt - Shell script formatting
- jq - JSON processing
- BATS - Testing framework
- Various utilities (curl, wget, git, make, etc.)

## Quick Start

### Prerequisites

- **Docker Desktop** (Windows/Mac) or **Docker Engine** (Linux)
- **VS Code** with **Dev Containers extension**

**Install Dev Containers extension:**
```bash
code --install-extension ms-vscode-remote.remote-containers
```

Or search for "Dev Containers" in VS Code extensions marketplace.

### Opening in Dev Container

**Method 1: Command Palette**
1. Open VS Code in the Jacker project directory
2. Press `F1` or `Ctrl+Shift+P` (Cmd+Shift+P on Mac)
3. Type "Dev Containers: Reopen in Container"
4. Select the command and wait for container to build

**Method 2: Notification**
1. Open the project in VS Code
2. Click "Reopen in Container" when prompted

**Method 3: Remote Indicator**
1. Click the green icon in bottom-left corner
2. Select "Reopen in Container"

### First Build

The first build will take 5-10 minutes:
1. Downloads base image (~500MB)
2. Installs features (Docker-in-Docker, common-utils, git)
3. Installs VS Code extensions
4. Runs post-create.sh script
5. Configures environment

**Subsequent opens:** ~30 seconds

### Verifying Setup

After the container opens:

```bash
# Check Docker
docker --version
docker compose version

# Check tools
bats --version
shellcheck --version
make --version

# Check Jacker
make help
```

## Development Workflow

### Starting Services

```bash
# From inside the dev container
make install    # First time setup
make up         # Start all services
make ps         # Check status
```

### Accessing Services

Services are automatically forwarded to your local machine:
- http://localhost:8080 - Traefik Dashboard
- http://localhost:3000 - Grafana
- http://localhost:9090 - Prometheus

**View forwarded ports:**
- Click "Ports" tab in VS Code terminal panel
- Or: Remote indicator (bottom-left) → "Forward a Port"

### Running Tests

```bash
# Unit tests (fast, no Docker required)
./tests/run_tests.sh unit

# Integration tests (requires Docker)
./tests/run_tests.sh integration

# All tests
./tests/run_tests.sh

# Or use Make
make test
```

### Using VS Code Tasks

Press `Ctrl+Shift+P` and type "Tasks: Run Task"

**Common tasks:**
- Start All Services (`Ctrl+Shift+B`)
- Run All Tests (`Ctrl+Shift+T`)
- Health Check
- View Logs
- CrowdSec Status

See `.vscode/tasks.json` for all 30+ available tasks.

## Customization

### Adding Packages

Edit `post-create.sh` to install additional packages:

```bash
sudo apt-get install -y package-name
```

Then rebuild container:
1. `Ctrl+Shift+P`
2. "Dev Containers: Rebuild Container"

### Adding VS Code Extensions

Edit `devcontainer.json`:

```json
"customizations": {
  "vscode": {
    "extensions": [
      "existing.extensions",
      "new.extension-id"
    ]
  }
}
```

Then rebuild container.

### Environment Variables

Add to `devcontainer.json`:

```json
"remoteEnv": {
  "MY_VAR": "value"
}
```

Or create `.env` file in the project root (gitignored).

### Mounting Additional Directories

Add to `mounts` array in `devcontainer.json`:

```json
"mounts": [
  "source=/path/on/host,target=/path/in/container,type=bind"
]
```

## Features Explained

### Docker-in-Docker

Allows running Docker commands inside the dev container:
- Build Docker images
- Run docker-compose
- Start/stop containers
- Access Docker socket

**Configuration:**
```json
"features": {
  "ghcr.io/devcontainers/features/docker-in-docker:2": {
    "version": "latest",
    "moby": true,
    "dockerDashComposeVersion": "v2"
  }
}
```

**Docker socket mounting:**
```json
"mounts": [
  "source=/var/run/docker.sock,target=/var/run/docker.sock,type=bind"
]
```

### Common Utilities

Installs common development tools:
- Zsh with Oh My Zsh
- Git with latest version
- Package upgrades
- User UID/GID synchronization

### Lifecycle Scripts

**postCreateCommand:** Runs once after container creation
- Used for: Installing dependencies, initial setup
- Script: `post-create.sh`

**postStartCommand:** Runs every time container starts
- Used for: Git safe directory config
- Quick commands only

**initializeCommand:** Runs on host before container starts
- Used for: Pre-flight checks

**onCreateCommand:** Runs after container creation
- Used for: One-time setup tasks

## Troubleshooting

### Container Won't Start

**Check Docker:**
```bash
docker --version
docker ps
```

**View logs:**
1. `Ctrl+Shift+P`
2. "Dev Containers: Show Container Log"

**Rebuild:**
1. `Ctrl+Shift+P`
2. "Dev Containers: Rebuild Container"

### Extension Not Working

**Reload window:**
1. `Ctrl+Shift+P`
2. "Developer: Reload Window"

**Check installed:**
- Extensions panel → Filter "Installed"

**Reinstall:**
- Remove from `devcontainer.json`
- Rebuild container
- Add back and rebuild again

### Port Already in Use

**Check host ports:**
```bash
# On host machine
lsof -i :8080
netstat -tuln | grep 8080
```

**Change port in devcontainer.json:**
```json
"forwardPorts": [8081]  // Instead of 8080
```

### Permission Denied

**Docker socket:**
```bash
# Inside container
ls -la /var/run/docker.sock
groups  # Should include 'docker'
```

**Fix:**
```bash
sudo usermod -aG docker $USER
# Then rebuild container
```

### Slow Performance

**Increase Docker resources:**
- Docker Desktop → Settings → Resources
- Increase CPUs and Memory

**Use bind mounts with consistency:**
```json
"mounts": [
  "source=${localWorkspaceFolder},target=/workspaces/jacker,type=bind,consistency=cached"
]
```

**WSL 2 (Windows):**
- Ensure project is in WSL filesystem, not /mnt/c/

## Advanced Configuration

### Multiple Dev Containers

Create variants for different purposes:

```
.devcontainer/
├── devcontainer.json          # Default
├── testing/
│   └── devcontainer.json      # Testing-focused
└── production/
    └── devcontainer.json      # Production-like
```

Open specific variant:
1. `Ctrl+Shift+P`
2. "Dev Containers: Reopen in Container"
3. Select configuration

### Docker Compose for Dev Container

Use `docker-compose.yml` instead of image:

```json
"dockerComposeFile": "docker-compose.dev.yml",
"service": "dev",
"workspaceFolder": "/workspaces/jacker"
```

### Dotfiles

Personal dotfiles repository for container customization:

```json
"dotfiles": {
  "repository": "username/dotfiles",
  "targetPath": "~/dotfiles",
  "installCommand": "~/dotfiles/install.sh"
}
```

### Features from Marketplace

Browse available features:
- https://containers.dev/features

Add to `features` object:
```json
"features": {
  "ghcr.io/devcontainers/features/python:1": {
    "version": "3.11"
  }
}
```

## Best Practices

### Do's ✅

- ✅ Commit `.devcontainer/` to git
- ✅ Keep base image updated
- ✅ Document custom configuration
- ✅ Use lifecycle scripts for setup
- ✅ Test configuration changes
- ✅ Use non-root user
- ✅ Forward only necessary ports

### Don'ts ❌

- ❌ Don't hardcode credentials
- ❌ Don't install too many extensions (slow)
- ❌ Don't modify container manually (won't persist)
- ❌ Don't run as root unless necessary
- ❌ Don't commit `.env` files
- ❌ Don't expose unnecessary ports

### Security

- Use official base images
- Run as non-root user (`remoteUser: "node"`)
- Keep packages updated
- Scan images for vulnerabilities
- Don't expose sensitive ports
- Use secrets for credentials

## GitHub Codespaces

This configuration works with GitHub Codespaces out of the box:

1. Go to GitHub repository
2. Click "Code" → "Codespaces"
3. Click "Create codespace on main"
4. Wait for environment to build

**Codespaces features:**
- Cloud-based development
- Access from anywhere
- Pre-configured environment
- Free tier available

## Resources

- [Dev Containers Documentation](https://code.visualstudio.com/docs/devcontainers/containers)
- [Dev Container Specification](https://containers.dev/)
- [Features Marketplace](https://containers.dev/features)
- [Dev Container Templates](https://containers.dev/templates)
- [GitHub Codespaces Docs](https://docs.github.com/en/codespaces)

## Contributing

When modifying dev container configuration:

1. Test changes locally first
2. Document new features/tools in this README
3. Update `post-create.sh` if needed
4. Commit changes with descriptive message
5. Notify team of any breaking changes

---

**Maintainer:** Jacker Team
**Last Updated:** 2025-10-11
**Container Version:** 1.0
