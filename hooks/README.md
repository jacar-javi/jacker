# Git Hooks for Jacker

This directory contains Git hooks that automatically run tests and validations to ensure code quality before commits and pushes.

## 🚀 Quick Start

```bash
# Install all hooks
./hooks/install.sh

# Uninstall hooks
./hooks/uninstall.sh
```

## 📋 Available Hooks

### pre-commit
Runs **quick validations** before each commit:
- ✅ ShellCheck validation for shell scripts
- ✅ YAML syntax validation
- ✅ Docker Compose configuration check
- ✅ Hardcoded secrets detection
- ✅ File permissions check
- ✅ Large file detection
- ✅ Trailing whitespace check

**Execution time:** ~5-10 seconds

### pre-push
Runs **comprehensive tests** before pushing to remote:
- ✅ All pre-commit checks
- ✅ Full repository ShellCheck scan
- ✅ Complete YAML validation
- ✅ Docker Compose service verification
- ✅ Required files check
- ✅ Documentation verification
- ✅ CLI functionality tests
- ✅ Template validation
- ✅ Security scanning
- ✅ Branch protection warnings

**Execution time:** ~30-60 seconds

### commit-msg
Validates **commit message format**:
- ✅ Conventional Commits format
- ✅ Subject line length check
- ✅ Type validation (feat, fix, docs, etc.)
- ✅ Format recommendations

**Expected format:**
```
<type>(<scope>): <subject>

<body>

<footer>
```

**Valid types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes
- `refactor`: Code refactoring
- `perf`: Performance improvements
- `test`: Test additions/changes
- `chore`: Maintenance tasks
- `build`: Build system changes
- `ci`: CI configuration changes
- `revert`: Reverting changes

**Examples:**
```bash
git commit -m "feat(auth): add OAuth2 authentication"
git commit -m "fix(docker): resolve compose validation errors"
git commit -m "docs: update installation instructions"
git commit -m "chore(deps): update Docker images"
```

## 🛠️ Installation

### Automatic Installation

```bash
# Run the installation script
./hooks/install.sh
```

The installer will:
1. Check for existing hooks
2. Offer to backup existing hooks
3. Install new hooks as symlinks
4. Check for required tools
5. Provide installation recommendations

### Manual Installation

```bash
# Make hooks executable
chmod +x hooks/*

# Create symlinks in .git/hooks
ln -sf ../../hooks/pre-commit .git/hooks/pre-commit
ln -sf ../../hooks/pre-push .git/hooks/pre-push
ln -sf ../../hooks/commit-msg .git/hooks/commit-msg
```

## 📦 Required Tools

For full functionality, install these tools:

### shellcheck
**Purpose:** Static analysis for shell scripts
```bash
# Ubuntu/Debian
apt-get install shellcheck

# macOS
brew install shellcheck

# Or download from GitHub
wget https://github.com/koalaman/shellcheck/releases/download/stable/shellcheck-stable.linux.x86_64.tar.xz
```

### yamllint
**Purpose:** YAML file validation
```bash
# Using pip
pip install yamllint

# Ubuntu/Debian
apt-get install yamllint

# macOS
brew install yamllint
```

### docker
**Purpose:** Docker Compose validation
```bash
# Install Docker
https://docs.docker.com/get-docker/
```

## ⚙️ Configuration

### Environment Variables

Control hook behavior with environment variables:

```bash
# Skip specific checks
SKIP_SHELLCHECK=1 git commit -m "fix: urgent fix"
SKIP_YAML_CHECK=1 git commit -m "feat: add feature"
SKIP_DOCKER_CHECK=1 git commit -m "docs: update docs"
```

### Bypassing Hooks

**Not recommended**, but if necessary:

```bash
# Bypass pre-commit and commit-msg hooks
git commit --no-verify -m "emergency fix"

# Bypass pre-push hook
git push --no-verify
```

## 🔍 Hook Details

### pre-commit Features

1. **Staged Files Detection**
   - Only validates files that are staged for commit
   - Skips validation if no files are staged

2. **ShellCheck Integration**
   - Validates shell scripts with error-level severity
   - Checks the main `jacker` CLI
   - Validates library modules

3. **YAML Validation**
   - Uses `yamllint` if available
   - Falls back to Python yaml module
   - Validates with relaxed rules

4. **Docker Compose Check**
   - Creates temporary .env if needed
   - Validates compose configuration
   - Cleans up temporary files

5. **Security Scanning**
   - Detects hardcoded passwords
   - Finds API keys and tokens
   - Skips .env files and templates

6. **File Checks**
   - Warns about files over 1MB
   - Checks executable permissions
   - Detects trailing whitespace

### pre-push Features

1. **Comprehensive Testing**
   - Runs all pre-commit checks
   - Adds extended validations
   - Tests across entire repository

2. **Service Verification**
   - Counts Docker services
   - Verifies service definitions
   - Checks for required services

3. **Documentation Check**
   - Verifies README files exist
   - Checks subdirectory documentation
   - Validates file structure

4. **CLI Testing**
   - Tests help command
   - Verifies version command
   - Checks script functionality

5. **Template Validation**
   - Counts template files
   - Verifies key templates exist
   - Checks template syntax

6. **Branch Protection**
   - Warns when pushing to main/master
   - Shows commits to be pushed
   - Validates commit message format

### commit-msg Features

1. **Conventional Commits**
   - Enforces standard format
   - Validates commit types
   - Checks scope format

2. **Message Quality**
   - Subject line length (72 chars recommended, 100 max)
   - Lowercase subject start
   - No trailing period
   - Body line wrapping

3. **Smart Detection**
   - Skips merge commits
   - Skips revert commits
   - Identifies issue references

## 📊 Performance

Hook execution times (approximate):

| Hook | Time | Impact |
|------|------|--------|
| pre-commit | 5-10s | Low - only staged files |
| pre-push | 30-60s | Medium - full validation |
| commit-msg | <1s | Minimal |

## 🐛 Troubleshooting

### Hook not executing

```bash
# Check if hook is installed
ls -la .git/hooks/

# Make hook executable
chmod +x hooks/*

# Reinstall hooks
./hooks/install.sh
```

### ShellCheck not found

```bash
# Install ShellCheck
apt-get install shellcheck

# Or download directly
wget -O- https://github.com/koalaman/shellcheck/releases/download/stable/shellcheck-stable.linux.x86_64.tar.xz | tar xJf -
```

### YAML validation failing

```bash
# Install yamllint
pip install yamllint

# Or use apt
apt-get install yamllint
```

### Docker Compose validation errors

```bash
# Ensure Docker is running
docker version

# Check .env file exists
cp .env.defaults .env
```

### Commit message rejected

```bash
# View expected format
cat hooks/commit-msg

# Use conventional format
git commit -m "type(scope): description"
```

## 🔄 Updating Hooks

Hooks are symlinked, so updates are automatic:

```bash
# Pull latest changes
git pull

# Hooks are automatically updated (symlinked)
# No reinstallation needed
```

## 🗑️ Uninstalling

```bash
# Run uninstall script
./hooks/uninstall.sh

# Or manually remove
rm .git/hooks/pre-commit
rm .git/hooks/pre-push
rm .git/hooks/commit-msg
```

## 📝 Contributing

When modifying hooks:

1. **Test locally first**
   ```bash
   # Test pre-commit
   ./hooks/pre-commit

   # Test with actual commit
   git add .
   git commit -m "test: testing hooks"
   ```

2. **Maintain performance**
   - Keep pre-commit under 10 seconds
   - Use parallel execution where possible
   - Cache results when appropriate

3. **Provide skip options**
   - Add environment variables for skipping
   - Document bypass methods
   - Explain when skipping is appropriate

4. **Follow conventions**
   - Use consistent colors
   - Provide clear error messages
   - Include fix suggestions

## 📚 Resources

- [Conventional Commits](https://www.conventionalcommits.org/)
- [Git Hooks Documentation](https://git-scm.com/book/en/v2/Customizing-Git-Git-Hooks)
- [ShellCheck Wiki](https://www.shellcheck.net/wiki/)
- [YAML Lint Rules](https://yamllint.readthedocs.io/en/stable/rules.html)

---

**Note:** These hooks are designed to maintain code quality without being overly restrictive. They can be bypassed when necessary, but regular use ensures consistent code quality across the project.