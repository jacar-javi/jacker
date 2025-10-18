# Jacker Interactive TUI - User Guide

## Introduction

The Jacker Interactive TUI (Text User Interface) provides a menu-driven interface for managing your Docker home server. It's perfect for users who prefer visual navigation over typing commands.

## Getting Started

### Prerequisites

Install dialog (recommended):
```bash
sudo apt-get install dialog
```

Or use whiptail (usually pre-installed):
```bash
sudo apt-get install whiptail
```

### Launch Interactive Mode

```bash
cd /path/to/jacker
./jacker --interactive
```

Or use the short form:
```bash
./jacker -i
```

## Navigation Guide

### Basic Controls

| Key | Action |
|-----|--------|
| ↑ ↓ | Navigate menu items |
| Enter | Select item / Confirm |
| Space | Toggle checkbox (in checklists) |
| Tab | Move between buttons |
| ESC | Cancel / Go back |

### Menu Hierarchy

```
Main Menu
├── Service Management
│   ├── Start All
│   ├── Stop All
│   ├── Restart All
│   ├── Start Selected (checklist)
│   ├── Stop Selected (checklist)
│   ├── Restart Selected (checklist)
│   └── Service Shell (radiolist)
├── Status & Monitoring
│   ├── View Status
│   ├── Watch Status (live)
│   ├── View Logs
│   ├── Follow Logs (live)
│   └── Run Health Check
├── Configuration
│   ├── Show Config
│   ├── Validate Config
│   ├── OAuth Setup
│   ├── Domain Setup
│   ├── SSL Setup
│   ├── Authentik Setup
│   └── Tracing Setup
├── Maintenance
│   ├── Backup
│   ├── Restore
│   ├── Update
│   ├── Check Updates
│   ├── Clean Up
│   ├── Wipe Data (dangerous!)
│   └── Tune Resources
├── Security
│   ├── Manage Secrets
│   ├── Security Scan
│   ├── Whitelist Management
│   └── View Alerts
├── Troubleshooting
│   ├── Fix Issues
│   ├── Diagnostics
│   ├── Network Issues
│   └── Permission Issues
└── System Information
    ├── System Info
    ├── Version Info
    ├── Docker Info
    └── Resource Usage
```

## Common Tasks

### Task 1: Start Specific Services

1. Launch TUI: `./jacker -i`
2. Select **"1. Service Management"**
3. Select **"4. Start Selected Services"**
4. Use ↑↓ to navigate, Space to check services
5. Press Enter when done
6. Confirm **"Yes"** to start

### Task 2: View Live Logs

1. Launch TUI: `./jacker -i`
2. Select **"2. Status & Monitoring"**
3. Select **"4. Follow Logs (Live)"**
4. Select service with ↑↓, press Enter
5. Logs stream in real-time
6. Press **Ctrl+C** to stop
7. Press Enter to return to menu

### Task 3: Run Health Check

1. Launch TUI: `./jacker -i`
2. Select **"2. Status & Monitoring"**
3. Select **"5. Run Health Check"**
4. Confirm **"Yes"**
5. View detailed health report
6. Press Enter to return to menu

### Task 4: Backup Configuration

1. Launch TUI: `./jacker -i`
2. Select **"4. Maintenance"**
3. Select **"1. Backup Configuration"**
4. Confirm **"Yes"**
5. Backup is created
6. Press Enter to continue

### Task 5: Access Service Shell

1. Launch TUI: `./jacker -i`
2. Select **"1. Service Management"**
3. Select **"7. Access Service Shell"**
4. Select service (radiolist - only one)
5. Press Enter
6. Shell opens (type `exit` to return)
7. Press Enter to return to menu

### Task 6: Configure OAuth

1. Launch TUI: `./jacker -i`
2. Select **"3. Configuration"**
3. Select **"3. Configure OAuth"**
4. Follow interactive prompts
5. Press Enter to return to menu

### Task 7: Manage IP Whitelist

1. Launch TUI: `./jacker -i`
2. Select **"5. Security"**
3. Select **"3. Manage Whitelist"**
4. Choose operation:
   - **"1. Show Whitelist"** - View current entries
   - **"2. Add Entry"** - Add IP/CIDR
   - **"3. Remove Entry"** - Remove IP/CIDR
   - **"4. Test Current IP"** - Check if your IP is whitelisted
   - **"5. Reload Whitelist"** - Apply changes

## Dialog Types Explained

### Menu (Selection)

```
┌──────────────────────────┐
│ Select an option:        │
├──────────────────────────┤
│   1. Option One          │
│ → 2. Option Two     ←    │
│   3. Option Three        │
└──────────────────────────┘
```

Use ↑↓ to select, Enter to confirm.

### Checklist (Multi-Select)

```
┌──────────────────────────┐
│ Select services:         │
├──────────────────────────┤
│ [X] traefik              │
│ [ ] redis           ←    │
│ [X] postgresql           │
└──────────────────────────┘
```

Use ↑↓ to navigate, Space to toggle, Enter when done.

### Radiolist (Single-Select)

```
┌──────────────────────────┐
│ Select one service:      │
├──────────────────────────┤
│ ( ) traefik              │
│ (•) redis           ←    │
│ ( ) postgresql           │
└──────────────────────────┘
```

Use ↑↓ to navigate, Enter to select.

### Yes/No Confirmation

```
┌──────────────────────────┐
│ Start all services?      │
├──────────────────────────┤
│   < Yes >   < No >       │
└──────────────────────────┘
```

Use ←→ or Tab to move between buttons, Enter to confirm.

### Input Box

```
┌──────────────────────────┐
│ Enter domain name:       │
├──────────────────────────┤
│ example.com_             │
├──────────────────────────┤
│   < OK >   < Cancel >    │
└──────────────────────────┘
```

Type your input, press Enter or Tab to OK.

### Message Box

```
┌──────────────────────────┐
│ Operation complete!      │
│                          │
│ All services started.    │
├──────────────────────────┤
│        < OK >            │
└──────────────────────────┘
```

Press Enter to dismiss.

## Tips & Tricks

### 🎯 Quick Tips

1. **ESC is Your Friend:** Press ESC to go back or cancel at any time
2. **Confirmations:** Destructive operations always ask for confirmation
3. **Service Selection:** Checklist = multiple, Radiolist = one only
4. **Live Operations:** Ctrl+C stops live logs/status, Enter returns to menu
5. **Shell Access:** Type `exit` to leave service shell and return to TUI

### 🚀 Power User Tips

1. **Combine with CLI:** You can use CLI commands alongside TUI
   ```bash
   # In another terminal while TUI is running:
   ./jacker logs traefik
   ```

2. **Quick Launch:** Create an alias
   ```bash
   echo "alias jtui='./jacker -i'" >> ~/.bashrc
   source ~/.bashrc
   jtui  # Quick launch!
   ```

3. **SSH Sessions:** Works great over SSH
   ```bash
   ssh user@server
   cd /path/to/jacker
   ./jacker -i
   ```

4. **Screen/Tmux:** Run in persistent sessions
   ```bash
   screen -S jacker
   ./jacker -i
   # Ctrl+A, D to detach
   # screen -r jacker to reattach
   ```

### ⚠️ Important Notes

1. **Data Wipe:** Option "Wipe All Data" requires TWO confirmations - it's permanent!
2. **Service Restarts:** Some config changes require service restart
3. **Docker Required:** Most operations need Docker to be running
4. **Terminal Size:** Best in 80x24 or larger terminal
5. **Read Messages:** Always read confirmation dialogs carefully

## Troubleshooting

### Issue: "Neither dialog nor whiptail found"

**Solution:**
```bash
sudo apt-get update
sudo apt-get install dialog
```

### Issue: Display looks broken

**Solution:**
- Resize terminal to at least 80x24
- Try a different terminal emulator
- Check terminal TERM variable: `echo $TERM`

### Issue: ESC not working

**Solution:**
- Try Ctrl+C instead
- Check if terminal is capturing ESC
- Use Tab to navigate to "Cancel" button

### Issue: Colors not showing

**Solution:**
- This is cosmetic only, TUI still works
- Try: `export TERM=xterm-256color`
- Use a terminal with better color support

### Issue: Can't select multiple services

**Solution:**
- Use Space bar to toggle checkboxes, not Enter
- Enter confirms selection after toggling

## Keyboard Reference

### Global Keys
- **↑** - Move up
- **↓** - Move down
- **←** - Previous button
- **→** - Next button
- **Enter** - Select/Confirm
- **Space** - Toggle (in checklists)
- **Tab** - Next button
- **Shift+Tab** - Previous button
- **ESC** - Cancel/Back
- **Ctrl+C** - Stop live operations

### In Service Shell
- **exit** - Return to TUI
- All normal shell commands work

### In Log View
- **Ctrl+C** - Stop following logs
- **Enter** - Return to menu (after stop)

## Examples Gallery

### Example 1: Starting Multiple Services

```
Step 1: Select "Service Management"
Step 2: Select "Start Selected Services"
Step 3: Checklist appears:
        [X] traefik
        [ ] homepage
        [X] redis
        [ ] postgresql
        [X] grafana
Step 4: Press Enter
Step 5: Confirm "Yes"
Result: Selected services start
```

### Example 2: Viewing Status

```
Step 1: Select "Status & Monitoring"
Step 2: Select "View Status"
Result: Status table displayed:
        traefik     running   2 hours
        redis       running   2 hours
        postgresql  stopped   -
```

### Example 3: Adding to Whitelist

```
Step 1: Select "Security"
Step 2: Select "Manage Whitelist"
Step 3: Select "Add Entry"
Step 4: Input box: "203.0.113.10"
Step 5: Press Enter
Result: IP added to whitelist
```

## FAQ

**Q: Can I use TUI and CLI at the same time?**
A: Yes! TUI doesn't lock anything. You can run CLI commands in another terminal.

**Q: Does TUI show real-time updates?**
A: Yes for "Watch Status" and "Follow Logs". Other operations show results after completion.

**Q: Can I exit TUI quickly?**
A: Press ESC on main menu, or select "8. Exit". Confirmation required.

**Q: Is TUI slower than CLI?**
A: No, TUI calls the same functions as CLI. Navigation overhead is minimal.

**Q: Can I customize the TUI?**
A: Not currently, but you can modify `/assets/lib/tui.sh` to customize.

**Q: Does TUI work over SSH?**
A: Yes! Works perfectly over SSH connections.

**Q: Can I script TUI operations?**
A: No, TUI is interactive only. Use CLI commands for scripting.

**Q: What if I make a mistake?**
A: ESC cancels most operations. Destructive operations have confirmations.

## Getting Help

### Within TUI
- Most menus have self-explanatory options
- Read confirmation dialogs carefully
- ESC always goes back safely

### CLI Help
```bash
./jacker --help           # General help
./jacker config --help    # Command-specific help
```

### Documentation
- `TUI_IMPLEMENTATION_REPORT.md` - Technical details
- `README.md` - General Jacker documentation

### Support
- GitHub Issues: Report bugs or request features
- Documentation: Read full docs at project repository

## Conclusion

The Jacker TUI makes Docker home server management accessible and intuitive. Whether you're a beginner or expert, the menu-driven interface provides easy access to all Jacker features.

**Happy Managing! 🚀**

---

**Quick Reference Card**

| Action | Key |
|--------|-----|
| Navigate | ↑↓ |
| Select | Enter |
| Toggle | Space |
| Back | ESC |
| Stop | Ctrl+C |
| Next Button | Tab |

Launch: `./jacker -i` or `./jacker --interactive`
