# Jaeger Volume Permission Fix

## Problem

Jaeger container fails to start with error:
```
mkdir /badger/key: permission denied
```

This happens when the Docker volume mounted at `/badger` doesn't have the correct ownership for the user running inside the container (UID 1000).

## Root Cause

1. Docker creates the host directory with root ownership when it doesn't exist
2. Jaeger container runs as user 1000:1000 (configured via PUID/PGID)
3. User 1000 inside container cannot create directories in root-owned volume

## Solutions

### Solution 1: Fix Volume Permissions (Quick Fix)

**Use this if you need persistent trace storage.**

Run the permission fix script:

```bash
cd /workspaces/jacker
./scripts/fix-jaeger-permissions.sh
```

The script will:
- Create the required directories (`badger/data`, `badger/key`, `tmp`)
- Set ownership to PUID:PGID (default 1000:1000)
- Set permissions to 755 (rwxr-xr-x)

Then restart Jaeger:

```bash
docker compose up -d jaeger
```

### Solution 2: Use tmpfs Storage (RECOMMENDED)

**Use this if traces don't need to persist across restarts.**

Jaeger traces are typically ephemeral - you usually only need recent traces for debugging. Using tmpfs provides:

✅ **Faster I/O** (in-memory storage)
✅ **No permission issues**
✅ **Automatic cleanup** on restart
✅ **Lower disk usage**

#### Steps to enable tmpfs:

1. Edit `compose/jaeger.yml`:

```yaml
volumes:
  # Persistent storage for traces
  # - $DATADIR/jaeger/badger:/badger  # COMMENT THIS OUT
  # Temporary files
  - $DATADIR/jaeger/tmp:/tmp
  # Sampling configuration
  - $CONFIGDIR/jaeger/sampling_strategies.json:/etc/jaeger/sampling_strategies.json:ro

# Use tmpfs for ephemeral badger storage (RECOMMENDED for better performance)
tmpfs:  # UNCOMMENT THESE LINES
  - /badger:rw,size=2g,uid=1000,gid=1000,mode=1777
```

2. Restart Jaeger:

```bash
docker compose up -d jaeger
```

The tmpfs mount:
- Allocates 2GB of RAM for trace storage
- Sets ownership to UID 1000, GID 1000 (matches container user)
- Uses mode 1777 (rwxrwxrwx with sticky bit) for maximum compatibility

## Verification

Check that Jaeger is running without errors:

```bash
# Check container status
docker ps | grep jaeger

# Check logs for errors
docker logs jaeger

# Verify health
docker inspect jaeger | jq '.[0].State.Health'
```

You should see:
- Container status: `Up`
- No permission errors in logs
- Health status: `healthy`

## When to Use Each Solution

| Scenario | Recommended Solution | Reason |
|----------|---------------------|---------|
| Development/Testing | **tmpfs** | Faster, simpler, traces don't need persistence |
| Production with short retention | **tmpfs** | Traces typically only needed for recent issues |
| Production with long retention | **Volume + Permissions** | Need historical trace data |
| Debugging permission issues | **tmpfs** | Eliminates permissions as a variable |

## Performance Comparison

| Storage Type | Read Speed | Write Speed | Persistence | Permission Issues |
|--------------|-----------|-------------|-------------|-------------------|
| tmpfs (RAM) | Very Fast | Very Fast | No | None |
| Volume (SSD) | Fast | Fast | Yes | Possible |
| Volume (HDD) | Medium | Medium | Yes | Possible |

## Additional Notes

### Trace Retention

Jaeger's default retention depends on storage:
- **Memory storage**: Configurable, typically 24 hours
- **Badger storage**: No automatic cleanup, grows indefinitely
- **tmpfs**: Cleared on container restart

For production, consider:
1. Using tmpfs with adequate size (2-4GB typically sufficient)
2. Exporting important traces to long-term storage
3. Using Jaeger with proper backend (Elasticsearch, Cassandra) for production scale

### Monitoring Storage Usage

If using volume storage, monitor disk usage:

```bash
# Check Jaeger data directory size
du -sh $DATADIR/jaeger/badger

# Check available space
df -h $DATADIR
```

If using tmpfs, monitor memory:

```bash
# Check tmpfs usage
docker exec jaeger df -h /badger

# Check container memory
docker stats jaeger --no-stream
```

## Troubleshooting

### Permission denied after running fix script

Check directory ownership:
```bash
ls -la $DATADIR/jaeger/badger
```

Should show ownership as your PUID:PGID (typically 1000:1000).

If not, manually fix:
```bash
sudo chown -R 1000:1000 $DATADIR/jaeger
sudo chmod -R 755 $DATADIR/jaeger
```

### tmpfs full error

Increase tmpfs size in `compose/jaeger.yml`:
```yaml
tmpfs:
  - /badger:rw,size=4g,uid=1000,gid=1000,mode=1777  # Increased to 4GB
```

### Container still failing

1. Check logs: `docker logs jaeger`
2. Verify user in container: `docker exec jaeger id`
3. Check mounted permissions: `docker exec jaeger ls -la /badger`
4. Verify PUID/PGID in .env match expected values

## References

- [Jaeger Documentation](https://www.jaegertracing.io/docs/latest/)
- [Badger Storage](https://www.jaegertracing.io/docs/latest/deployment/#badger---local-storage)
- [Docker tmpfs mounts](https://docs.docker.com/storage/tmpfs/)
