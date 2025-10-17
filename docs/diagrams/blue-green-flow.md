# Blue-Green Deployment Flow Diagram

## High-Level Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                   Blue-Green Deployment Flow                    │
└─────────────────────────────────────────────────────────────────┘

                         ┌──────────────┐
                         │    START     │
                         └──────┬───────┘
                                │
                    ┌───────────▼───────────┐
                    │  PHASE 1: PREPARATION │
                    └───────────┬───────────┘
                                │
         ┌──────────────────────┼──────────────────────┐
         │                      │                      │
    ┌────▼────┐          ┌─────▼──────┐        ┌─────▼─────┐
    │ Validate│          │ Get Current│        │  Create   │
    │ Service │          │   Limits   │        │Green Config│
    └────┬────┘          └─────┬──────┘        └─────┬─────┘
         │                     │                     │
         └──────────────────────┼─────────────────────┘
                                │
                    ┌───────────▼────────────┐
                    │ PHASE 2: DEPLOY GREEN  │
                    └───────────┬────────────┘
                                │
                         ┌──────▼──────┐
                         │Scale to 2   │
                         │Replicas     │
                         │(Blue+Green) │
                         └──────┬──────┘
                                │
                    ┌───────────▼────────────┐
                    │ PHASE 3: HEALTH CHECK  │
                    └───────────┬────────────┘
                                │
                         ┌──────▼──────┐
                         │Wait for     │
                         │Green Healthy│
                         │(120s max)   │
                         └──────┬──────┘
                                │
                         ┌──────▼──────┐
                         │  Healthy?   │
                         └──────┬──────┘
                                │
                  ┌─────────────┴─────────────┐
                  │                           │
              ┌───▼───┐                  ┌────▼────┐
              │  YES  │                  │   NO    │
              └───┬───┘                  └────┬────┘
                  │                           │
                  │                    ┌──────▼──────┐
                  │                    │  ROLLBACK   │
                  │                    │  TO BLUE    │
                  │                    └──────┬──────┘
                  │                           │
                  │                      ┌────▼────┐
                  │                      │  FAIL   │
                  │                      └─────────┘
                  │
      ┌───────────▼────────────┐
      │PHASE 4: VERIFY TRAFFIC │
      └───────────┬────────────┘
                  │
           ┌──────▼──────┐
           │  Traefik    │
           │Load Balancing│
           │ Blue+Green  │
           └──────┬──────┘
                  │
      ┌───────────▼─────────────┐
      │PHASE 5: REMOVE BLUE     │
      └───────────┬─────────────┘
                  │
           ┌──────▼──────┐
           │Drain        │
           │Connections  │
           │(30s)        │
           └──────┬──────┘
                  │
           ┌──────▼──────┐
           │Scale to 1   │
           │(Green only) │
           └──────┬──────┘
                  │
      ┌───────────▼─────────────┐
      │PHASE 6: VERIFICATION    │
      └───────────┬─────────────┘
                  │
           ┌──────▼──────┐
           │Final Health │
           │   Check     │
           └──────┬──────┘
                  │
           ┌──────▼──────┐
           │  SUCCESS    │
           └─────────────┘
```

## Detailed State Diagram

```
┌────────────────────────────────────────────────────────────────────┐
│                      Service State During Deployment               │
└────────────────────────────────────────────────────────────────────┘

BEFORE DEPLOYMENT:
┌─────────────────────┐
│   Blue (Running)    │  ← Current service
│  CPU: 1.0, Mem: 512M│
│  Status: healthy    │
└─────────────────────┘


PHASE 2: Deploy Green
┌─────────────────────┐     ┌─────────────────────┐
│   Blue (Running)    │     │   Green (Starting)  │
│  CPU: 1.0, Mem: 512M│     │  CPU: 1.5, Mem: 768M│
│  Status: healthy    │     │  Status: starting   │
└─────────────────────┘     └─────────────────────┘
         ▲                           │
         │    Traffic: 100%          │  Traffic: 0%
         └───────────────────────────┘


PHASE 3-4: Both Running (Health Check + Traffic Split)
┌─────────────────────┐     ┌─────────────────────┐
│   Blue (Running)    │     │   Green (Running)   │
│  CPU: 1.0, Mem: 512M│     │  CPU: 1.5, Mem: 768M│
│  Status: healthy    │     │  Status: healthy    │
└─────────────────────┘     └─────────────────────┘
         ▲                           ▲
         │    Traffic: 50%  Traffic: 50%  ← Traefik LB
         └──────────────┬────────────┘
                        │
                ┌───────▼────────┐
                │   Traefik      │
                │ Load Balancer  │
                └────────────────┘


PHASE 5: Remove Blue
                            ┌─────────────────────┐
                            │   Green (Running)   │
                            │  CPU: 1.5, Mem: 768M│
                            │  Status: healthy    │
                            └─────────────────────┘
                                     ▲
                                     │  Traffic: 100%
                            ┌────────┴────────┐
                            │   Traefik       │
                            │ Load Balancer   │
                            └─────────────────┘


AFTER DEPLOYMENT:
┌─────────────────────┐
│  Green (Running)    │  ← New service (was Green, now Blue)
│  CPU: 1.5, Mem: 768M│
│  Status: healthy    │
└─────────────────────┘
```

## Rollback Flow

```
┌────────────────────────────────────────────────────────────────┐
│                        Rollback Scenario                        │
└────────────────────────────────────────────────────────────────┘

                    ┌──────────────┐
                    │Green FAILS   │
                    │Health Check  │
                    └──────┬───────┘
                           │
                    ┌──────▼──────┐
                    │Auto-Rollback│
                    │  Triggered  │
                    └──────┬──────┘
                           │
              ┌────────────┴────────────┐
              │                         │
       ┌──────▼──────┐          ┌──────▼──────┐
       │ Remove Green│          │Restore Blue │
       │  Container  │          │Configuration│
       └──────┬──────┘          └──────┬──────┘
              │                         │
              └────────────┬────────────┘
                           │
                    ┌──────▼──────┐
                    │Scale to 1   │
                    │(Blue only)  │
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │Verify Blue  │
                    │  Healthy    │
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │  RESTORED   │
                    │(No Downtime)│
                    └─────────────┘


KEY: Service NEVER went down - Blue kept running the entire time!
```

## Traffic Flow During Deployment

```
┌────────────────────────────────────────────────────────────────┐
│                    Traffic Flow Timeline                        │
└────────────────────────────────────────────────────────────────┘

Time: T0 (Before Deployment)
┌──────────┐
│  Users   │
└────┬─────┘
     │
     ▼
┌─────────────┐        ┌──────────────┐
│  Traefik    │───────▶│     Blue     │
└─────────────┘        └──────────────┘
   100% Traffic


Time: T1 (Deploy Green)
┌──────────┐
│  Users   │
└────┬─────┘
     │
     ▼
┌─────────────┐        ┌──────────────┐
│  Traefik    │───────▶│     Blue     │
└─────────────┘        └──────────────┘
   100% Traffic        ┌──────────────┐
                       │  Green       │ (Starting, no traffic)
                       └──────────────┘


Time: T2 (Both Healthy - Load Balanced)
┌──────────┐
│  Users   │
└────┬─────┘
     │
     ▼
┌─────────────┐        ┌──────────────┐
│  Traefik    │───────▶│     Blue     │ (50% traffic)
│             │        └──────────────┘
└─────┬───────┘
      │                ┌──────────────┐
      └───────────────▶│    Green     │ (50% traffic)
                       └──────────────┘


Time: T3 (Remove Blue)
┌──────────┐
│  Users   │
└────┬─────┘
     │
     ▼
┌─────────────┐        ┌──────────────┐
│  Traefik    │───────▶│    Green     │ (100% traffic)
└─────────────┘        └──────────────┘


RESULT: Zero Downtime - Users never experience service interruption!
```

## Health Check Polling

```
┌────────────────────────────────────────────────────────────────┐
│                   Health Check Process                          │
└────────────────────────────────────────────────────────────────┘

Start: Green Container Started
  │
  ├─ T=0s   ──▶ Poll: "starting"  ⏳ Wait 5s
  ├─ T=5s   ──▶ Poll: "starting"  ⏳ Wait 5s
  ├─ T=10s  ──▶ Poll: "starting"  ⏳ Wait 5s
  ├─ T=15s  ──▶ Poll: "starting"  ⏳ Wait 5s
  ├─ T=20s  ──▶ Poll: "healthy"   ✓ SUCCESS!
  │
  └─ Continue to traffic verification

If T > 120s and still "starting":
  │
  └─ TIMEOUT ──▶ Rollback to Blue


Health Check Command (example for Grafana):
  docker inspect <container> --format='{{.State.Health.Status}}'

Expected Values:
  - "starting"  : Health check running but not complete
  - "healthy"   : Health check passed
  - "unhealthy" : Health check failed
  - "none"      : No health check defined (fallback to "running")
```

## Resource Override Mechanism

```
┌────────────────────────────────────────────────────────────────┐
│              Docker Compose Override Pattern                    │
└────────────────────────────────────────────────────────────────┘

1. Base Configuration (docker-compose.yml):
   ┌───────────────────────────────────┐
   │ services:                          │
   │   grafana:                         │
   │     deploy:                        │
   │       resources:                   │
   │         limits:                    │
   │           cpus: "1.0"              │
   │           memory: 512M             │
   └───────────────────────────────────┘

2. Override Created (docker-compose.blue-green.yml):
   ┌───────────────────────────────────┐
   │ services:                          │
   │   grafana:                         │
   │     deploy:                        │
   │       resources:                   │
   │         limits:                    │
   │           cpus: "1.5"              │
   │           memory: 768M             │
   │     labels:                        │
   │       - deployment.type=blue-green │
   └───────────────────────────────────┘

3. Deployment Command:
   docker-compose -f docker-compose.yml \
                  -f docker-compose.blue-green.yml \
                  up -d --scale grafana=2

4. Result:
   ┌───────────────────────────────────┐
   │ Blue Container (existing):         │
   │   CPU: 1.0, Memory: 512M          │
   │   (keeps original limits)          │
   └───────────────────────────────────┘

   ┌───────────────────────────────────┐
   │ Green Container (new):             │
   │   CPU: 1.5, Memory: 768M          │
   │   (gets override limits)           │
   └───────────────────────────────────┘
```

## Error Handling Flow

```
┌────────────────────────────────────────────────────────────────┐
│                    Error Scenarios                              │
└────────────────────────────────────────────────────────────────┘

Error Type: Service Not Found
  Validate Service ──▶ NOT FOUND ──▶ EXIT(1)

Error Type: Stateful Service
  Validate Service ──▶ IS STATEFUL ──▶ WARN ──▶ EXIT(1)
                                           │
                                    (unless --force)

Error Type: No Health Check
  Validate Service ──▶ NO HEALTHCHECK ──▶ WARN ──▶ EXIT(1)
                                               │
                                        (unless --force)

Error Type: Scale Up Fails
  Scale Up Green ──▶ FAILS ──▶ Rollback ──▶ EXIT(2)

Error Type: Health Check Timeout
  Wait for Healthy ──▶ TIMEOUT ──▶ Rollback ──▶ EXIT(4)

Error Type: Scale Down Fails
  Scale Down Blue ──▶ FAILS ──▶ Rollback ──▶ EXIT(2)

Error Type: Verification Fails
  Verify Deployment ──▶ FAILS ──▶ Rollback ──▶ EXIT(2)


Note: All errors trigger automatic rollback (unless --no-rollback)
      Service continues running on Blue during entire process
```

## Monitoring Checkpoints

```
┌────────────────────────────────────────────────────────────────┐
│                  What to Monitor When                           │
└────────────────────────────────────────────────────────────────┘

Phase 1: Preparation
  Monitor: Script output for validation errors
  Action:  Fix configuration if errors

Phase 2: Deploy Green
  Monitor: docker-compose output
  Action:  Check container starts successfully

Phase 3: Health Check
  Monitor: docker logs <service>
  Action:  Look for startup errors, OOM, crashes

Phase 4: Traffic Verification
  Monitor: Traefik dashboard, service metrics
  Action:  Verify both replicas receiving traffic

Phase 5: Remove Blue
  Monitor: Connection count, active sessions
  Action:  Wait for draining to complete

Phase 6: Verification
  Monitor: Final health status, resource usage
  Action:  Verify Green is stable

Post-Deployment
  Monitor: Service metrics for next 10-15 minutes
  Action:  Watch for memory leaks, performance issues
```
