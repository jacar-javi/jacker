# VSCode Terminal Preview

## What You'll See When Opening a New Terminal

```
╔══════════════════════════════════════════════════════════╗
║          JACKER INFRASTRUCTURE - SYSTEM INFO             ║
╚══════════════════════════════════════════════════════════╝

🖥️  CPU Information:
   Model: Intel(R) Core(TM) i7-9700K CPU @ 3.60GHz
   Cores: 8 cores, 8 threads
   Frequency: 3.60 GHz
   Cache: 12288 KB

💾 Memory Information:
   Total RAM: 31.3 GB
   Available: 24.5 GB (78%)
   Swap: 8.0 GB

💿 Disk Information:
   Total: 931.5G
   Available: 456.2G (51% used)
   Type: SSD

🌐 Network Information:
   eth0: 172.20.0.10
   docker0: 172.17.0.1

🐧 System Information:
   OS: Ubuntu 22.04.3 LTS
   Kernel: 5.15.167.4-microsoft-standard-WSL2
   Uptime: 2 days, 14 hours
   Load: 1.23 0.98 0.76

🐳 Docker Information:
   Version: 24.0.7
   Containers: 12/15 running

📊 PERFORMANCE SCORE: 95/100
    [████████████████████████████░░] Excellent Performance Server


Welcome to Jacker Infrastructure VSCode Environment
Type 'jacker' to navigate to project root, 'sysinfo' to display system info

(jacker) abc@vscode:/data/jacker (main)$ _
```

## Prompt Breakdown

### Format
```
(jacker) user@host:/current/path (git-branch)$
```

### Color Scheme
- `(jacker)` - **Cyan** - Project identifier
- `user@host` - **Green** - User and hostname
- `/current/path` - **Blue** - Current directory
- `(git-branch)` - **Yellow** - Git branch (if in repo)
- `$` - **Reset** - Command prompt

## Example Terminal Session

```bash
# Terminal opens with system info displayed above

(jacker) abc@vscode:/data/jacker (main)$ jacker
(jacker) abc@vscode:/data/jacker (main)$

(jacker) abc@vscode:/data/jacker (main)$ gs
On branch main
Your branch is up to date with 'origin/main'.

nothing to commit, working tree clean

(jacker) abc@vscode:/data/jacker (main)$ dc ps
NAME            IMAGE                                     COMMAND                  SERVICE     CREATED       STATUS                 PORTS
traefik         traefik:latest                            "/entrypoint.sh --..."   traefik     2 days ago    Up 2 days (healthy)    0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp
postgres        postgres:16-alpine                        "docker-entrypoint..."   postgres    2 days ago    Up 2 days (healthy)    5432/tcp
...

(jacker) abc@vscode:/data/jacker (main)$ clogs traefik
Attaching to traefik
traefik | time="2025-10-17T12:34:56Z" level=info msg="Configuration loaded"
traefik | time="2025-10-17T12:34:57Z" level=info msg="Server listening"
^C

(jacker) abc@vscode:/data/jacker (main)$ compose
(jacker) abc@vscode:/data/jacker/compose (main)$ ll
total 68K
drwxr-xr-x  2 abc abc 4.0K Oct 17 00:21 ./
drwxr-xr-x 15 abc abc 4.0K Oct 17 00:21 ../
-rw-r--r--  1 abc abc 1.2K Oct 17 00:19 alertmanager.yml
-rw-r--r--  1 abc abc 2.3K Oct 17 00:19 authentik.yml
...

(jacker) abc@vscode:/data/jacker/compose (main)$ ..
(jacker) abc@vscode:/data/jacker (main)$

(jacker) abc@vscode:/data/jacker (main)$ dnetwork
NAMES           NETWORKS            PORTS
traefik         traefik_proxy       0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp
postgres        traefik_proxy       5432/tcp
redis           traefik_proxy       6379/tcp
...

(jacker) abc@vscode:/data/jacker (main)$ meminfo
               total        used        free      shared  buff/cache   available
Mem:            31Gi       6.8Gi        24Gi       123Mi       1.2Gi        24Gi
Swap:          8.0Gi          0B       8.0Gi

(jacker) abc@vscode:/data/jacker (main)$ restart traefik
Restarting traefik ... done

(jacker) abc@vscode:/data/jacker (main)$ sysinfo
╔══════════════════════════════════════════════════════════╗
║          JACKER INFRASTRUCTURE - SYSTEM INFO             ║
╚══════════════════════════════════════════════════════════╝
[... system info displays again ...]

(jacker) abc@vscode:/data/jacker (main)$
```

## Available Quick Commands

### Navigation
```bash
jacker          # Jump to /data/jacker
home            # Jump to /data/home
logs            # Jump to /data/jacker/logs
compose         # Jump to /data/jacker/compose
configs         # Jump to /data/jacker/config
scripts         # Jump to /data/jacker/scripts
```

### Docker Compose
```bash
dc              # docker compose
dcup            # docker compose up -d
dcdown          # docker compose down
dcrestart       # docker compose restart
dcps            # docker compose ps
dclogs          # docker compose logs -f
```

### Docker
```bash
dps             # docker ps
dpsa            # docker ps -a
dimages         # docker images
dnetwork        # Show containers with networks
```

### Git
```bash
gs              # git status
ga              # git add
gc              # git commit
gp              # git push
gl              # git log --oneline --graph
gd              # git diff
```

### System
```bash
ll              # ls -lah (detailed listing)
sysinfo         # Display system info
ports           # Show all ports (netstat)
meminfo         # Show memory info
diskusage       # Show disk usage
```

### Custom Functions
```bash
clogs <name>    # View container logs
cexec <name>    # Execute command in container
restart <name>  # Restart compose service
dclean          # Clean up Docker resources
```

## Disabling System Info

If you find the system info too verbose, disable it:

```bash
# Add to your shell environment
export JACKER_DISABLE_SYSINFO=1

# Then open new terminal
```

When disabled, you'll see:
```
Welcome to Jacker Infrastructure VSCode Environment
Type 'jacker' to navigate to project root, 'sysinfo' to display system info

(jacker) abc@vscode:/data/jacker (main)$ _
```

And you can manually trigger it with: `sysinfo`

## Git Branch Indicator

The prompt automatically shows your current git branch:

```bash
# In main branch
(jacker) abc@vscode:/data/jacker (main)$

# In feature branch
(jacker) abc@vscode:/data/jacker (feature/new-feature)$

# Not in git repo
(jacker) abc@vscode:/tmp$
```

## History Features

### Timestamped History
```bash
(jacker) abc@vscode:/data/jacker (main)$ history
    1  2025-10-17 12:34:56 jacker
    2  2025-10-17 12:35:10 gs
    3  2025-10-17 12:35:25 dc ps
    4  2025-10-17 12:36:40 clogs traefik
```

### Duplicate Removal
```bash
# Running same command multiple times only saves once
(jacker) abc@vscode:/data/jacker (main)$ gs
(jacker) abc@vscode:/data/jacker (main)$ gs
(jacker) abc@vscode:/data/jacker (main)$ gs
(jacker) abc@vscode:/data/jacker (main)$ history | tail -1
    5  2025-10-17 12:37:00 gs
# Only one entry for 'gs'
```

## Tab Completion

Standard bash tab completion works with all aliases:

```bash
(jacker) abc@vscode:/data/jacker (main)$ dc<TAB>
dc          dcbuild     dcdown      dclogs      dcps        dcpull      dcrestart   dcup

(jacker) abc@vscode:/data/jacker (main)$ g<TAB>
ga     gb     gc     gco    gd     gl     gp     grep   gs
```

## Error Handling

Commands provide helpful output when used incorrectly:

```bash
(jacker) abc@vscode:/data/jacker (main)$ clogs
Usage: clogs <container-name>
NAMES           STATUS                   PORTS
traefik         Up 2 days (healthy)      0.0.0.0:80->80/tcp, :::80->80/tcp, 0.0.0.0:443->443/tcp, :::443->443/tcp
postgres        Up 2 days (healthy)      5432/tcp
...

(jacker) abc@vscode:/data/jacker (main)$ restart
Usage: restart <service-name>
alertmanager
authentik
blackbox-exporter
...

(jacker) abc@vscode:/data/jacker (main)$ cexec
Usage: cexec <container-name> [command]
NAMES           STATUS
traefik         Up 2 days
postgres        Up 2 days
...
```

## Performance

### Fast Startup
```
Terminal opens: ~0.05s
System info displays: ~0.05s
Ready for input: ~0.1s total
```

### Minimal Resource Usage
```
Memory overhead: < 1MB
CPU usage: Negligible
No background processes
```

## Customization

All settings are in: `/workspaces/jacker/config/vscode/.bashrc`

Edit and restart container to apply changes:
```bash
docker compose restart vscode
```

---

*This preview shows what your VSCode terminal will look like after the integration is complete and the container is restarted.*
