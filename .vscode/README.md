# VS Code Configuration for Jacker

This directory contains Visual Studio Code configuration files for the Jacker project, providing a consistent development environment across all contributors.

## Files Overview

### `extensions.json`
**Recommended VS Code extensions for Jacker development**

**Shell Scripting:**
- `timonwong.shellcheck` - ShellCheck linter for bash scripts
- `foxundermoon.shell-format` - Bash script formatter
- `mads-hartmann.bash-ide-vscode` - Bash IDE with autocomplete and goto definition

**Docker & Containers:**
- `ms-azuretools.vscode-docker` - Docker support (compose files, images, containers)
- `ms-vscode-remote.remote-containers` - Dev Containers support

**YAML & Configuration:**
- `redhat.vscode-yaml` - YAML language support with schema validation
- `dotenv.dotenv-vscode` - .env file syntax highlighting

**Testing:**
- `jetmartin.bats` - BATS test file support

**Code Quality:**
- `editorconfig.editorconfig` - EditorConfig support
- `streetsidesoftware.code-spell-checker` - Spell checking

**Utilities:**
- `gruntfuggly.todo-tree` - TODO/FIXME highlighting
- `aaron-bond.better-comments` - Enhanced comment highlighting

### `settings.json`
**Project-specific VS Code settings**

**Key Features:**
- **Shell Formatting:** Auto-format on save with 4-space indentation
- **ShellCheck Integration:** Lint on save, follow sourced files
- **YAML Schemas:** Validate docker-compose, Prometheus, GitHub workflows
- **File Associations:** Correct syntax for .bats, .env.*, Makefile
- **Search Exclusions:** Skip data/, logs/, node_modules/ in searches
- **Spell Checker:** Custom dictionary with Jacker-specific terms
- **Terminal:** Default to bash with 10k line scrollback

**Shell Format Settings:**
```json
"shellformat.flag": "-i 4 -ci -sr -bn"
```
- `-i 4` - 4-space indentation
- `-ci` - Indent case statements
- `-sr` - Redirect operators on same line
- `-bn` - Binary operators at beginning of line

**ShellCheck Configuration:**
```json
"shellcheck.exclude": [
  "SC1090", // Can't follow non-constant source
  "SC1091"  // Not following sourced files
]
```

### `tasks.json`
**VS Code tasks for common Jacker operations**

**Available Tasks:**

**Installation & Setup:**
- Install Jacker
- Reinstall Jacker
- Setup BATS Testing

**Service Management:**
- Start All Services (⌘+Shift+B)
- Stop All Services
- Restart Services
- View Service Status
- View Logs (All Services)
- Follow Logs (background task)

**Health & Monitoring:**
- Health Check
- Watch Health Status (background task)
- View Resource Usage

**Testing:**
- Run All Tests (⌘+Shift+T)
- Run Unit Tests
- Run Integration Tests
- Run ShellCheck
- Lint All Scripts

**Backup & Restore:**
- Create Backup

**Stack Management:**
- List Available Stacks
- List Installed Stacks

**Configuration:**
- Validate Configuration
- Show Docker Compose Config
- Show Environment Variables

**CrowdSec:**
- CrowdSec Status
- CrowdSec Decisions

**Maintenance:**
- Update All Images

**Running Tasks:**
1. Press `Ctrl+Shift+P` (or `Cmd+Shift+P` on Mac)
2. Type "Tasks: Run Task"
3. Select the task to run

**Keyboard Shortcuts:**
- `Ctrl+Shift+B` / `Cmd+Shift+B` - Start All Services (default build task)
- `Ctrl+Shift+T` / `Cmd+Shift+T` - Run All Tests (default test task)

### `launch.json`
**Debug configurations for shell scripts**

**Available Configurations:**
- **Debug Shell Script** - Debug the currently open .sh file
- **Debug Setup Script** - Debug assets/setup.sh with DEBUG=1
- **Debug Stack Script** - Debug assets/stack.sh with arguments
- **Run BATS Test File** - Run the currently open .bats test file
- **Docker: Attach to Container** - Attach debugger to running container

**Requirements:**
- Bash Debug extension (optional, for advanced debugging)
- For script debugging: `set -x` in the script or `bash -x script.sh`

### `snippets.code-snippets`
**Code snippets for faster development**

**Available Snippets:**

**BATS Testing:**
- `bats-test` - Create a BATS test case
- `bats-setup` - Create BATS setup function
- `bats-teardown` - Create BATS teardown function

**Bash Scripts:**
- `bash-header` - Standard Jacker script header with error handling
- `source-lib` - Source a library from assets/lib/
- `func-doc` - Documented function template
- `error-handler` - Error handling function
- `check-prereq` - Check for required commands
- `confirm` - User confirmation prompt

**Docker Compose:**
- `compose-service` - Complete service definition with Traefik labels

**Makefile:**
- `make-target` - Makefile target with help comment

**Usage:**
1. Start typing the snippet prefix (e.g., `bats-test`)
2. Press `Tab` to expand
3. Fill in the placeholder values
4. Press `Tab` to move to the next placeholder

## Quick Start

### 1. Install Recommended Extensions

When you open the project, VS Code will prompt you to install recommended extensions. Click "Install All" to get the full development experience.

Alternatively, run:
```bash
code --install-extension timonwong.shellcheck
code --install-extension foxundermoon.shell-format
# ... etc
```

### 2. Verify ShellCheck

ShellCheck should automatically lint your shell scripts. Look for squiggly underlines in .sh and .bats files.

If ShellCheck is not working:
```bash
# Install ShellCheck
sudo apt-get install shellcheck  # Ubuntu/Debian
brew install shellcheck           # macOS
```

### 3. Run a Task

Press `Ctrl+Shift+P`, type "Tasks: Run Task", and select "Health Check" to verify your setup.

### 4. Use Code Snippets

In a .sh file, type `bash-header` and press Tab to insert a complete script header.

## Customization

### User Settings vs Workspace Settings

**Workspace settings** (`.vscode/settings.json`):
- Shared across all contributors
- Committed to git
- Project-specific configurations

**User settings** (`~/.config/Code/User/settings.json`):
- Personal preferences
- Not committed to git
- Override workspace settings

To override workspace settings:
1. Open Settings UI: `Ctrl+,` / `Cmd+,`
2. Change the setting
3. It will be saved to your user settings

### Adding Custom Tasks

Edit `.vscode/tasks.json` and add a new task:
```json
{
  "label": "My Custom Task",
  "type": "shell",
  "command": "make my-target",
  "problemMatcher": [],
  "presentation": {
    "reveal": "always"
  }
}
```

### Adding Custom Snippets

Edit `.vscode/snippets.code-snippets` and add:
```json
"My Snippet": {
  "prefix": "mysnip",
  "scope": "shellscript",
  "body": [
    "echo \"${1:Hello}\"",
    "${2:# More code}"
  ],
  "description": "My custom snippet"
}
```

## Troubleshooting

### ShellCheck Not Working

**Problem:** No linting errors shown for shell scripts

**Solutions:**
1. Install ShellCheck: `sudo apt-get install shellcheck`
2. Reload VS Code: `Ctrl+Shift+P` → "Developer: Reload Window"
3. Check output: `Ctrl+Shift+U` → Select "ShellCheck" from dropdown

### Shell Format Not Working

**Problem:** Scripts not formatting on save

**Solutions:**
1. Check extension installed: Extensions panel → Search "Shell Format"
2. Verify setting: `"editor.formatOnSave": true` in settings.json
3. Try manual format: Right-click → "Format Document"

### YAML Validation Errors

**Problem:** False positives in docker-compose.yml

**Solutions:**
1. Check schema mapping in settings.json
2. Disable for specific file: Add `# yaml-language-server: $schema=null` at top
3. Update YAML extension

### Tasks Not Appearing

**Problem:** Tasks not listed in "Run Task" menu

**Solutions:**
1. Reload VS Code
2. Check tasks.json syntax: Valid JSON
3. Open Output: `Ctrl+Shift+U` → "Tasks"

## Advanced Features

### Workspace Trust

Jacker's .vscode configuration includes tasks that run shell commands. VS Code may require you to "Trust" the workspace:

1. Click "Trust Workspace" when prompted
2. Or: `Ctrl+Shift+P` → "Workspaces: Manage Workspace Trust"

### Multi-Root Workspaces

If working on multiple related projects, create a workspace file:

```json
{
  "folders": [
    { "path": "." },
    { "path": "../jacker-stacks" }
  ],
  "settings": {
    "files.exclude": {
      "**/node_modules": true
    }
  }
}
```

Save as `jacker.code-workspace` and open with:
```bash
code jacker.code-workspace
```

### Remote Development

The configuration works with:
- **Remote-SSH** - Develop on remote servers
- **Dev Containers** - Develop inside Docker containers
- **WSL** - Windows Subsystem for Linux

All extensions and settings sync automatically.

## Integration with Other Tools

### EditorConfig

Create `.editorconfig` in project root for editor-agnostic settings:
```ini
[*.sh]
indent_style = space
indent_size = 4
end_of_line = lf
insert_final_newline = true
```

### Pre-commit Hooks

The VS Code configuration complements git pre-commit hooks:
```bash
#!/bin/bash
# .git/hooks/pre-commit
shellcheck assets/*.sh assets/**/*.sh
```

### GitHub Actions

VS Code settings align with CI configuration:
```yaml
# .github/workflows/lint.yml
- name: ShellCheck
  run: shellcheck assets/**/*.sh
```

## Contributing

When contributing to Jacker:

1. **Install recommended extensions** - Ensures consistent linting and formatting
2. **Use code snippets** - Maintains consistent code patterns
3. **Run tasks before committing** - `make lint` and `make test`
4. **Don't commit user-specific settings** - Keep `.vscode/` for shared config only

## Resources

- [VS Code Documentation](https://code.visualstudio.com/docs)
- [ShellCheck Wiki](https://www.shellcheck.net/wiki/)
- [BATS Documentation](https://bats-core.readthedocs.io/)
- [Docker Extension Docs](https://code.visualstudio.com/docs/containers/overview)
- [YAML Extension Docs](https://github.com/redhat-developer/vscode-yaml)

---

**Note:** This configuration is committed to git and shared across all contributors. Personal preferences should be set in your user settings, not in this workspace configuration.
