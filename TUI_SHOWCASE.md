# Jacker TUI - Visual Showcase

## Overview

This document provides visual examples of the Jacker Interactive TUI interface.

## Main Menu

```
┌────────────────────────────────────────────────────────────────────────┐
│          Jacker - Docker Home Server Management Platform v3.0.0        │
└────────────────────────────────────────────────────────────────────────┘

┌─────────────────────── Jacker Main Menu ──────────────────────────────┐
│                                                                        │
│ Select an operation:                                                   │
│                                                                        │
│        1. Service Management                                           │
│        2. Status & Monitoring                                          │
│        3. Configuration                                                │
│        4. Maintenance                                                  │
│        5. Security                                                     │
│        6. Troubleshooting                                              │
│        7. System Information                                           │
│        8. Exit                                                         │
│                                                                        │
│                                                                        │
│                    < OK >          < Cancel >                          │
└────────────────────────────────────────────────────────────────────────┘
```

## Service Management Menu

```
┌────────────────────────────────────────────────────────────────────────┐
│          Jacker - Docker Home Server Management Platform v3.0.0        │
└────────────────────────────────────────────────────────────────────────┘

┌──────────────────── Service Management ───────────────────────────────┐
│                                                                        │
│ Select service operation:                                              │
│                                                                        │
│        1. Start All Services                                           │
│        2. Stop All Services                                            │
│        3. Restart All Services                                         │
│        4. Start Selected Services                                      │
│        5. Stop Selected Services                                       │
│        6. Restart Selected Services                                    │
│        7. Access Service Shell                                         │
│        8. Back to Main Menu                                            │
│                                                                        │
│                    < OK >          < Cancel >                          │
└────────────────────────────────────────────────────────────────────────┘
```

## Service Selection (Checklist)

```
┌────────────────────────────────────────────────────────────────────────┐
│          Jacker - Docker Home Server Management Platform v3.0.0        │
└────────────────────────────────────────────────────────────────────────┘

┌─────────────────────── Start Services ────────────────────────────────┐
│                                                                        │
│ Select services to start:                                              │
│                                                                        │
│    [X] traefik                                                         │
│    [ ] homepage                                                        │
│    [X] redis                                                           │
│    [ ] postgresql                                                      │
│    [X] grafana                                                         │
│    [ ] prometheus                                                      │
│    [X] loki                                                            │
│    [ ] crowdsec                                                        │
│    [ ] portainer                                                       │
│                                                                        │
│                    < OK >          < Cancel >                          │
└────────────────────────────────────────────────────────────────────────┘

Navigation: ↑↓ to move, Space to toggle, Enter to confirm
```

## Service Shell Selection (Radiolist)

```
┌────────────────────────────────────────────────────────────────────────┐
│          Jacker - Docker Home Server Management Platform v3.0.0        │
└────────────────────────────────────────────────────────────────────────┘

┌───────────────────── Service Shell ───────────────────────────────────┐
│                                                                        │
│ Select service for shell access:                                       │
│                                                                        │
│    ( ) traefik                                                         │
│    (•) redis                                                           │
│    ( ) postgresql                                                      │
│    ( ) grafana                                                         │
│    ( ) prometheus                                                      │
│    ( ) loki                                                            │
│    ( ) crowdsec                                                        │
│    ( ) portainer                                                       │
│                                                                        │
│                    < OK >          < Cancel >                          │
└────────────────────────────────────────────────────────────────────────┘

Navigation: ↑↓ to move, Enter to select
```

## Confirmation Dialog

```
┌────────────────────────────────────────────────────────────────────────┐
│          Jacker - Docker Home Server Management Platform v3.0.0        │
└────────────────────────────────────────────────────────────────────────┘

┌──────────────────── Confirm Start ────────────────────────────────────┐
│                                                                        │
│ Start selected services:                                               │
│                                                                        │
│ traefik redis grafana loki                                             │
│                                                                        │
│                                                                        │
│                    < Yes >          < No >                             │
└────────────────────────────────────────────────────────────────────────┘
```

## Status & Monitoring Menu

```
┌────────────────────────────────────────────────────────────────────────┐
│          Jacker - Docker Home Server Management Platform v3.0.0        │
└────────────────────────────────────────────────────────────────────────┘

┌─────────────────── Status & Monitoring ───────────────────────────────┐
│                                                                        │
│ Select monitoring operation:                                           │
│                                                                        │
│        1. View Status                                                  │
│        2. Watch Status (Live)                                          │
│        3. View Logs                                                    │
│        4. Follow Logs (Live)                                           │
│        5. Run Health Check                                             │
│        6. Back to Main Menu                                            │
│                                                                        │
│                                                                        │
│                    < OK >          < Cancel >                          │
└────────────────────────────────────────────────────────────────────────┘
```

## Progress Indicator

```
┌────────────────────────────────────────────────────────────────────────┐
│          Jacker - Docker Home Server Management Platform v3.0.0        │
└────────────────────────────────────────────────────────────────────────┘

┌────────────────── Starting Services ──────────────────────────────────┐
│                                                                        │
│ Please wait...                                                         │
│                                                                        │
│ ████████████████████████████████████░░░░░░░░░░░░  75%                 │
│                                                                        │
│ # Finalizing...                                                        │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

## Message Box (Success)

```
┌────────────────────────────────────────────────────────────────────────┐
│          Jacker - Docker Home Server Management Platform v3.0.0        │
└────────────────────────────────────────────────────────────────────────┘

┌───────────────────── Complete ────────────────────────────────────────┐
│                                                                        │
│ All services have been started.                                        │
│                                                                        │
│                                                                        │
│                           < OK >                                       │
└────────────────────────────────────────────────────────────────────────┘
```

## Input Box

```
┌────────────────────────────────────────────────────────────────────────┐
│          Jacker - Docker Home Server Management Platform v3.0.0        │
└────────────────────────────────────────────────────────────────────────┘

┌────────────────── Configure Domain ───────────────────────────────────┐
│                                                                        │
│ Enter domain name:                                                     │
│                                                                        │
│ ┌────────────────────────────────────────────────────────────────┐    │
│ │ example.com                                                    │    │
│ └────────────────────────────────────────────────────────────────┘    │
│                                                                        │
│                    < OK >          < Cancel >                          │
└────────────────────────────────────────────────────────────────────────┘
```

## Configuration Menu

```
┌────────────────────────────────────────────────────────────────────────┐
│          Jacker - Docker Home Server Management Platform v3.0.0        │
└────────────────────────────────────────────────────────────────────────┘

┌──────────────────── Configuration ────────────────────────────────────┐
│                                                                        │
│ Select configuration operation:                                        │
│                                                                        │
│        1. Show Configuration                                           │
│        2. Validate Configuration                                       │
│        3. Configure OAuth                                              │
│        4. Configure Domain                                             │
│        5. Configure SSL                                                │
│        6. Configure Authentik                                          │
│        7. Configure Tracing                                            │
│        8. Back to Main Menu                                            │
│                                                                        │
│                    < OK >          < Cancel >                          │
└────────────────────────────────────────────────────────────────────────┘
```

## Maintenance Menu

```
┌────────────────────────────────────────────────────────────────────────┐
│          Jacker - Docker Home Server Management Platform v3.0.0        │
└────────────────────────────────────────────────────────────────────────┘

┌───────────────────── Maintenance ─────────────────────────────────────┐
│                                                                        │
│ Select maintenance operation:                                          │
│                                                                        │
│        1. Backup Configuration                                         │
│        2. Restore from Backup                                          │
│        3. Update Jacker                                                │
│        4. Check for Updates                                            │
│        5. Clean Up                                                     │
│        6. Wipe All Data                                                │
│        7. Tune Resources                                               │
│        8. Back to Main Menu                                            │
│                                                                        │
│                    < OK >          < Cancel >                          │
└────────────────────────────────────────────────────────────────────────┘
```

## Dangerous Operation Warning

```
┌────────────────────────────────────────────────────────────────────────┐
│          Jacker - Docker Home Server Management Platform v3.0.0        │
└────────────────────────────────────────────────────────────────────────┘

┌────────────────────── DANGER! ────────────────────────────────────────┐
│                                                                        │
│ Wipe ALL data?                                                         │
│                                                                        │
│ This is IRREVERSIBLE!                                                  │
│                                                                        │
│ SSL certs will be preserved.                                           │
│                                                                        │
│                    < Yes >          < No >                             │
└────────────────────────────────────────────────────────────────────────┘

┌─────────────────── Final Confirmation ────────────────────────────────┐
│                                                                        │
│ Are you ABSOLUTELY SURE?                                               │
│                                                                        │
│ All data will be lost!                                                 │
│                                                                        │
│                    < Yes >          < No >                             │
└────────────────────────────────────────────────────────────────────────┘
```

## Security Menu

```
┌────────────────────────────────────────────────────────────────────────┐
│          Jacker - Docker Home Server Management Platform v3.0.0        │
└────────────────────────────────────────────────────────────────────────┘

┌───────────────────── Security ────────────────────────────────────────┐
│                                                                        │
│ Select security operation:                                             │
│                                                                        │
│        1. Manage Secrets                                               │
│        2. Security Scan                                                │
│        3. Manage Whitelist                                             │
│        4. View Alerts                                                  │
│        5. Back to Main Menu                                            │
│                                                                        │
│                                                                        │
│                    < OK >          < Cancel >                          │
└────────────────────────────────────────────────────────────────────────┘
```

## Whitelist Management Submenu

```
┌────────────────────────────────────────────────────────────────────────┐
│          Jacker - Docker Home Server Management Platform v3.0.0        │
└────────────────────────────────────────────────────────────────────────┘

┌─────────────────── Whitelist Management ──────────────────────────────┐
│                                                                        │
│ Select whitelist operation:                                            │
│                                                                        │
│        1. Show Whitelist                                               │
│        2. Add Entry                                                    │
│        3. Remove Entry                                                 │
│        4. Test Current IP                                              │
│        5. Reload Whitelist                                             │
│        6. Back                                                         │
│                                                                        │
│                    < OK >          < Cancel >                          │
└────────────────────────────────────────────────────────────────────────┘
```

## Troubleshooting Menu

```
┌────────────────────────────────────────────────────────────────────────┐
│          Jacker - Docker Home Server Management Platform v3.0.0        │
└────────────────────────────────────────────────────────────────────────┘

┌──────────────────── Troubleshooting ──────────────────────────────────┐
│                                                                        │
│ Select troubleshooting operation:                                      │
│                                                                        │
│        1. Fix Common Issues                                            │
│        2. View Diagnostics                                             │
│        3. Network Issues                                               │
│        4. Permission Issues                                            │
│        5. Back to Main Menu                                            │
│                                                                        │
│                                                                        │
│                    < OK >          < Cancel >                          │
└────────────────────────────────────────────────────────────────────────┘
```

## System Information Menu

```
┌────────────────────────────────────────────────────────────────────────┐
│          Jacker - Docker Home Server Management Platform v3.0.0        │
└────────────────────────────────────────────────────────────────────────┘

┌────────────────── System Information ─────────────────────────────────┐
│                                                                        │
│ Select information to display:                                         │
│                                                                        │
│        1. System Info                                                  │
│        2. Version Info                                                 │
│        3. Docker Info                                                  │
│        4. Resource Usage                                               │
│        5. Back to Main Menu                                            │
│                                                                        │
│                                                                        │
│                    < OK >          < Cancel >                          │
└────────────────────────────────────────────────────────────────────────┘
```

## Welcome Screen

```
┌────────────────────────────────────────────────────────────────────────┐
│          Jacker - Docker Home Server Management Platform v3.0.0        │
└────────────────────────────────────────────────────────────────────────┘

┌──────────────────── Welcome to Jacker ────────────────────────────────┐
│                                                                        │
│ Welcome to the Jacker Interactive Menu!                                │
│                                                                        │
│ Use arrow keys to navigate, Enter to select.                           │
│ Press ESC to go back or cancel.                                        │
│                                                                        │
│ Version: 3.0.0                                                         │
│                                                                        │
│                           < OK >                                       │
└────────────────────────────────────────────────────────────────────────┘
```

## Exit Confirmation

```
┌────────────────────────────────────────────────────────────────────────┐
│          Jacker - Docker Home Server Management Platform v3.0.0        │
└────────────────────────────────────────────────────────────────────────┘

┌──────────────────────── Exit ─────────────────────────────────────────┐
│                                                                        │
│ Exit Jacker interactive mode?                                          │
│                                                                        │
│                                                                        │
│                    < Yes >          < No >                             │
└────────────────────────────────────────────────────────────────────────┘

When you select Yes:

Thank you for using Jacker!
$
```

## Navigation Flow Examples

### Example 1: Starting Services

```
Main Menu
    → 1. Service Management
        → 4. Start Selected Services
            → [Checklist of services]
                → Space to toggle selections
                → Enter to confirm
                    → Yes/No confirmation
                        → Services start
                            → Success message
                                → Back to Service Menu
```

### Example 2: Viewing Logs

```
Main Menu
    → 2. Status & Monitoring
        → 4. Follow Logs (Live)
            → [Radiolist of services]
                → Select service
                → Enter to confirm
                    → Logs stream (Ctrl+C to stop)
                        → Press Enter to continue
                            → Back to Status Menu
```

### Example 3: Creating Backup

```
Main Menu
    → 4. Maintenance
        → 1. Backup Configuration
            → Yes/No confirmation
                → Backup creates
                    → Success message
                        → Back to Maintenance Menu
```

## Color Scheme

- **Backtitle:** Blue background
- **Menu Title:** Bold white
- **Selected Item:** Highlighted
- **Buttons:** White on blue (selected)
- **Border:** Line drawing characters

## Terminal Requirements

- **Minimum Size:** 80 columns × 24 rows
- **Recommended:** 100 columns × 30 rows
- **Color Support:** Optional (works in monochrome)
- **UTF-8:** Recommended for best display

## Quick Reference

### Launch
```bash
./jacker -i
./jacker --interactive
```

### Navigation Keys
- **↑↓** - Move through menu
- **Enter** - Select/Confirm
- **Space** - Toggle checkbox
- **Tab** - Next button
- **ESC** - Cancel/Back
- **Ctrl+C** - Stop operation

### Dialog Types
- **Menu** - Select one option
- **Checklist** - Select multiple (Space to toggle)
- **Radiolist** - Select one (arrow keys + Enter)
- **Yes/No** - Confirmation (arrow keys between buttons)
- **Input Box** - Text entry
- **Message Box** - Information display
- **Gauge** - Progress bar

## Accessibility

- Keyboard-only navigation (no mouse required)
- Clear visual hierarchy
- Consistent button placement
- Confirmation for destructive actions
- ESC always goes back safely

## Performance

- Instant menu display
- No lag on navigation
- Fast service list building
- Minimal resource usage
- Works over slow SSH connections

---

**This TUI implementation provides an intuitive, powerful interface for managing your Jacker home server without memorizing commands.**
