# OAuth Client Secret Rotation Guide

## CRITICAL VULNERABILITY - IMMEDIATE ACTION REQUIRED

**Status:** The production Google OAuth client secret is exposed in plaintext in:
- `.env` file (Line 32: `OAUTH_CLIENT_SECRET=GOCSPX-...`)
- `compose/oauth.yml` environment variables (Line 51)
- Git history (multiple commits)

**Impact:** Anyone with access to the git repository or `.env` file can impersonate your OAuth application and potentially gain unauthorized access to protected services.

**Estimated Downtime:** 5-10 minutes during secret rotation

**Last Updated:** 2025-10-18

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Pre-Rotation Checklist](#pre-rotation-checklist)
3. [Step-by-Step Rotation Procedure](#step-by-step-rotation-procedure)
4. [Verification & Testing](#verification--testing)
5. [Rollback Procedure](#rollback-procedure)
6. [Post-Rotation Cleanup](#post-rotation-cleanup)
7. [Security Best Practices](#security-best-practices)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before beginning this procedure, ensure you have:

- [ ] **Google Cloud Console Access** - Project owner or editor role for OAuth credential management
- [ ] **SSH Access to VPS1** - Username: `ubuntu`, Host: `193.70.40.21`
- [ ] **Local Jacker Repository** - Located at `/workspaces/jacker` or equivalent
- [ ] **Backup Access Method** - Alternative way to access VPS1 if OAuth fails (console access)
- [ ] **15-30 Minutes of Time** - Do not rush this procedure
- [ ] **Team Notification** - Inform users that OAuth authentication will be briefly unavailable

**Required Tools:**
- SSH client
- Text editor (nano, vim, or VS Code)
- Web browser (for Google Cloud Console and testing)
- Git (for optional history cleanup)

---

## Pre-Rotation Checklist

### 1. Verify Current OAuth Configuration

**On your local machine:**

```bash
cd /workspaces/jacker

# Verify the exposed secret exists
grep "OAUTH_CLIENT_SECRET" .env

# Expected output:
# OAUTH_CLIENT_SECRET=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
```

**On VPS1:**

```bash
ssh ubuntu@193.70.40.21

# Check OAuth service status
docker ps --filter name=oauth

# Verify OAuth is running and healthy
docker logs oauth --tail 20

# Exit VPS1
exit
```

### 2. Create Backup Points

**Backup current configuration:**

```bash
# On local machine
cd /workspaces/jacker

# Create backup branch
git checkout -b backup-before-oauth-rotation-$(date +%Y%m%d)
git push origin backup-before-oauth-rotation-$(date +%Y%m%d)

# Return to main branch
git checkout main
```

**Backup on VPS1:**

```bash
ssh ubuntu@193.70.40.21

# Backup current .env file
cp /home/ubuntu/jacker/.env /home/ubuntu/jacker/.env.backup-$(date +%Y%m%d)

# Backup current compose file
cp /home/ubuntu/jacker/compose/oauth.yml /home/ubuntu/jacker/compose/oauth.yml.backup

# Verify backups
ls -lh /home/ubuntu/jacker/*.backup*

exit
```

### 3. Document Current OAuth Client ID

**In Google Cloud Console:**

1. Navigate to: https://console.cloud.google.com/apis/credentials
2. Locate your OAuth 2.0 Client ID (should be: `1059260209846-tl3k4aedjb4jeotvr1ovvrvo5thqbvv4.apps.googleusercontent.com`)
3. Document the current configuration:
   - Client ID: `1059260209846-tl3k4aedjb4jeotvr1ovvrvo5thqbvv4.apps.googleusercontent.com`
   - Authorized redirect URIs: `https://oauth.vps1.jacarsystems.net/oauth2/callback`
   - Current secret: `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` (TO BE ROTATED)

---

## Step-by-Step Rotation Procedure

### Part A: Generate New Secret in Google Cloud Console

**WARNING:** The new secret will only be shown ONCE. Copy it immediately and store it securely.

1. **Navigate to Google Cloud Console**
   - URL: https://console.cloud.google.com/apis/credentials
   - Select your project (if you have multiple)

2. **Locate OAuth 2.0 Client ID**
   - Look for "OAuth 2.0 Client IDs" section
   - Find the client with ID: `1059260209846-tl3k4aedjb4jeotvr1ovvrvo5thqbvv4`
   - Type should be "Web application"

3. **Add New Client Secret**
   - Click the pencil/edit icon (✏️) next to your OAuth client
   - Scroll down to the "Client secrets" section
   - Click **"+ ADD SECRET"** button (NOT "Delete")
   - A new secret will be generated automatically

4. **Copy the New Secret IMMEDIATELY**
   - A dialog will appear showing the new client secret
   - Format: `GOCSPX-XXXXXXXXXXXXXXXXXXXXXXXXXXXX`
   - **CRITICAL:** Click the copy icon or manually select and copy the secret
   - Paste it into a secure temporary location (password manager or secure text file)
   - Click "OK" or "Done"

5. **Verify Two Secrets Exist**
   - You should now see TWO client secrets listed
   - Old secret: `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`
   - New secret: `GOCSPX-XXXXXXXXXXXXXXXXXXXXXXXXXXXX` (partially hidden)
   - **DO NOT delete the old secret yet** (needed for rollback)

6. **Click "SAVE"**
   - Save the OAuth client configuration
   - Both secrets are now active and valid

**Checkpoint:** You should have the new secret copied and both secrets active in Google Cloud Console.

---

### Part B: Create Docker Secret on VPS1

**This stores the new secret securely in Docker Swarm/Compose secrets.**

```bash
# SSH to VPS1
ssh ubuntu@193.70.40.21

# Navigate to jacker directory
cd /home/ubuntu/jacker

# Create Docker secret with the NEW client secret
# Replace PASTE_NEW_SECRET_HERE with the actual secret from Google Cloud Console
echo "PASTE_NEW_SECRET_HERE" | docker secret create oauth_client_secret -

# Example (DO NOT use this - use YOUR new secret):
# echo "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5O6P" | docker secret create oauth_client_secret -
```

**Verify Secret Creation:**

```bash
# List Docker secrets
docker secret ls

# Expected output should include:
# ID              NAME                    DRIVER    CREATED          UPDATED
# xxxxxx          oauth_client_secret               X seconds ago    X seconds ago
# xxxxxx          oauth_cookie_secret               ...              ...
# xxxxxx          redis_oauth_password              ...              ...
```

**If secret creation fails with "secret already exists":**

```bash
# Remove the existing secret (if it exists from previous attempts)
docker secret rm oauth_client_secret

# Try creating again
echo "PASTE_NEW_SECRET_HERE" | docker secret create oauth_client_secret -
```

**Checkpoint:** Docker secret `oauth_client_secret` is now created and contains the new Google OAuth secret.

---

### Part C: Update compose/oauth.yml Configuration

**Edit the compose file to use Docker secret instead of environment variable.**

```bash
# Still on VPS1, edit the oauth compose file
nano /home/ubuntu/jacker/compose/oauth.yml

# Or use vim if you prefer:
# vim /home/ubuntu/jacker/compose/oauth.yml
```

**FIND these lines (around line 47-51):**

```yaml
    environment:
      # OAuth Provider Configuration
      - OAUTH2_PROXY_PROVIDER=google
      - OAUTH2_PROXY_CLIENT_ID=${OAUTH_CLIENT_ID}
      - OAUTH2_PROXY_CLIENT_SECRET=${OAUTH_CLIENT_SECRET}
      - OAUTH2_PROXY_REDIRECT_URL=https://oauth.${PUBLIC_FQDN}/oauth2/callback
```

**REPLACE the OAUTH2_PROXY_CLIENT_SECRET line with a comment:**

```yaml
    environment:
      # OAuth Provider Configuration
      - OAUTH2_PROXY_PROVIDER=google
      - OAUTH2_PROXY_CLIENT_ID=${OAUTH_CLIENT_ID}
      # Client secret now loaded from Docker secret file (see secrets section above)
      - OAUTH2_PROXY_REDIRECT_URL=https://oauth.${PUBLIC_FQDN}/oauth2/callback
```

**NOTE:** The `secrets:` section already exists at lines 31-34, so we don't need to add it:

```yaml
    secrets:
      - oauth_client_secret      # ← Already configured!
      - oauth_cookie_secret
      - redis_oauth_password
```

**FIND the config file reference (around line 2-8):**

```yaml
    command:
      - --config=/etc/oauth2-proxy/oauth2-proxy.cfg
```

**VERIFY the config file will handle the secret:**

The configuration file at `/workspaces/jacker/config/oauth2-proxy/oauth2-proxy.cfg` already has a placeholder for client_secret (line 3), but we need to ensure OAuth2-Proxy reads from the Docker secret file instead.

**ADD a command flag to use the secret file (around line 7-8):**

```yaml
    command:
      - --config=/etc/oauth2-proxy/oauth2-proxy.cfg
      - --client-secret-file=/run/secrets/oauth_client_secret
```

**IMPORTANT:** The `--client-secret-file` flag takes precedence over the config file and environment variables.

**Save and exit:**
- If using nano: Press `Ctrl+X`, then `Y`, then `Enter`
- If using vim: Press `Esc`, type `:wq`, press `Enter`

**Verify your changes:**

```bash
# Check that the secret is referenced correctly
grep -A 5 "secrets:" /home/ubuntu/jacker/compose/oauth.yml | head -10

# Expected output should show:
# secrets:
#   - oauth_client_secret
#   - oauth_cookie_secret
#   - redis_oauth_password

# Check that environment variable is removed
grep "OAUTH2_PROXY_CLIENT_SECRET" /home/ubuntu/jacker/compose/oauth.yml

# Expected output: Only a comment line (or nothing if you removed it completely)

# Check that command flag is added
grep "client-secret-file" /home/ubuntu/jacker/compose/oauth.yml

# Expected output:
#   - --client-secret-file=/run/secrets/oauth_client_secret
```

**Checkpoint:** The compose file is now configured to read the OAuth client secret from Docker secrets instead of environment variables.

---

### Part D: Deploy Updated Configuration to VPS1

**Restart the OAuth service with the new configuration.**

```bash
# Still on VPS1
cd /home/ubuntu/jacker

# Pull the latest configuration (if you made changes locally and pushed)
# Skip this if you edited directly on VPS1
# git pull origin main

# Validate the compose file syntax
docker compose -f compose/oauth.yml config >/dev/null

# If the above command succeeds (no output), the syntax is valid

# Restart OAuth service with new configuration
docker compose up -d oauth

# Expected output:
# [+] Running 1/1
#  ✔ Container oauth  Started
```

**Monitor the startup:**

```bash
# Wait for OAuth to initialize
sleep 10

# Check container status
docker ps --filter name=oauth

# Expected output:
# CONTAINER ID   IMAGE                                     STATUS          NAMES
# xxxxxxxxxxxx   quay.io/oauth2-proxy/oauth2-proxy:v7.7.1  Up X seconds    oauth

# Check logs for successful startup
docker logs oauth --tail 50

# Expected log entries (look for these):
# [2025/10/18 10:00:00] [oauthproxy.go:xxx] OAuthProxy configured for google Client ID: 1059260209846-...
# [2025/10/18 10:00:00] [oauthproxy.go:xxx] mapping path "/oauth2" => upstream "..."
# [2025/10/18 10:00:00] [oauthproxy.go:xxx] listening on http://0.0.0.0:4180
```

**Check for errors:**

```bash
# Look for any errors in the logs
docker logs oauth 2>&1 | grep -i error

# If you see errors like:
# "error reading client secret file" → Check that Docker secret exists
# "invalid client secret" → Check that you copied the correct secret from Google Cloud Console
# "failed to connect to redis" → Verify Redis is running and redis_oauth_password secret is correct
```

**If no errors, OAuth is running with the new secret!**

---

### Part E: Update Local Repository (Optional but Recommended)

**Update your local compose file to match the VPS1 configuration.**

```bash
# On your local machine
cd /workspaces/jacker

# Edit compose/oauth.yml
# Apply the same changes as in Part C above

# Or if you edited on VPS1, pull the changes:
scp ubuntu@193.70.40.21:/home/ubuntu/jacker/compose/oauth.yml compose/oauth.yml

# Verify the change
grep -A 5 "command:" compose/oauth.yml | grep "client-secret-file"

# Expected output:
#   - --client-secret-file=/run/secrets/oauth_client_secret
```

---

## Verification & Testing

### Step 1: Test OAuth Flow

**Open a private/incognito browser window** (to avoid cached cookies):

```
Test URL: https://traefik.vps1.jacarsystems.net
```

**Expected Flow:**

1. **Redirect to OAuth Login**
   - You should be redirected to `https://oauth.vps1.jacarsystems.net/oauth2/start`
   - Then redirected to Google's OAuth login page

2. **Google Account Selection**
   - Select your authorized Google account
   - Or sign in if not already signed in

3. **OAuth Consent** (if prompted)
   - May ask for permission to access your email/profile
   - Click "Allow" or "Continue"

4. **Redirect Back to Application**
   - You should be redirected to `https://oauth.vps1.jacarsystems.net/oauth2/callback`
   - Then to the original URL: `https://traefik.vps1.jacarsystems.net`

5. **Access Granted**
   - Traefik dashboard should load successfully
   - No authentication errors in browser console (F12)

**Success Indicators:**

- ✅ No "Invalid client secret" errors
- ✅ No "Failed to exchange authorization code" errors
- ✅ OAuth cookie is set (check browser DevTools → Application → Cookies → `_oauth2_proxy`)
- ✅ Can access protected resources without re-authenticating

**Failure Indicators:**

- ❌ "OAuth2 error: invalid_client" → Check that new secret matches Google Cloud Console
- ❌ "Failed to redeem code" → Check that client secret is correctly loaded from Docker secret
- ❌ Infinite redirect loop → Check Traefik middleware configuration
- ❌ "502 Bad Gateway" → OAuth service failed to start, check logs

**If OAuth fails, see [Rollback Procedure](#rollback-procedure) below.**

---

### Step 2: Verify Docker Secret is Being Used

```bash
# SSH to VPS1
ssh ubuntu@193.70.40.21

# Check that the secret file is mounted in the container
docker exec oauth ls -la /run/secrets/

# Expected output should include:
# -r--r--r-- 1 root root XX oauth_client_secret
# -r--r--r-- 1 root root XX oauth_cookie_secret
# -r--r--r-- 1 root root XX redis_oauth_password

# Verify the secret file contains data (DO NOT print it!)
docker exec oauth wc -c /run/secrets/oauth_client_secret

# Expected output: A number greater than 0 (e.g., "47 /run/secrets/oauth_client_secret")

# Check OAuth logs confirm secret file is being used
docker logs oauth 2>&1 | grep -i "client.*secret"

# Expected: No errors about missing or invalid client secret
```

---

### Step 3: Test Multiple Protected Services

**Test access to other OAuth-protected services:**

```
1. https://portainer.vps1.jacarsystems.net  → Should work with same OAuth session
2. https://grafana.vps1.jacarsystems.net     → Should work with same OAuth session
3. https://prometheus.vps1.jacarsystems.net  → Should work with same OAuth session
```

**Expected:** All services should work without re-authentication (session stored in Redis).

**If any service fails:**
- Check Traefik middleware configuration in `config/traefik/rules/middlewares-oauth.yml`
- Check that the service has the correct middleware applied
- Check OAuth logs for errors: `docker logs oauth --follow`

---

### Step 4: Test Session Persistence

```bash
# Close browser completely
# Wait 30 seconds
# Re-open browser and navigate to: https://traefik.vps1.jacarsystems.net

# Expected: Still authenticated (session stored in Redis)
# If prompted to log in again, check:
# - Redis is running and accessible
# - Redis OAuth user password is correct
# - OAuth session store is configured correctly
```

---

## Rollback Procedure

**If OAuth authentication fails after rotation, rollback immediately.**

### Option 1: Revert to Environment Variable (Fast)

```bash
# SSH to VPS1
ssh ubuntu@193.70.40.21
cd /home/ubuntu/jacker

# Edit compose/oauth.yml
nano /home/ubuntu/jacker/compose/oauth.yml

# REMOVE the command flag:
# - --client-secret-file=/run/secrets/oauth_client_secret

# ADD back the environment variable:
# - OAUTH2_PROXY_CLIENT_SECRET=${OAUTH_CLIENT_SECRET}

# Save and exit

# Restart OAuth service
docker compose up -d oauth

# Wait 10 seconds
sleep 10

# Check status
docker logs oauth --tail 30

# Test OAuth flow
# Navigate to: https://traefik.vps1.jacarsystems.net
```

**This uses the old secret from .env file (still valid in Google Cloud Console).**

---

### Option 2: Restore from Backup (Full)

```bash
# SSH to VPS1
ssh ubuntu@193.70.40.21
cd /home/ubuntu/jacker

# Restore backup compose file
cp /home/ubuntu/jacker/compose/oauth.yml.backup /home/ubuntu/jacker/compose/oauth.yml

# Restart OAuth service
docker compose up -d oauth

# Test OAuth flow
```

---

### Option 3: Delete New Secret and Use Old (Nuclear)

**Only if Options 1 & 2 fail and you need to completely revert:**

1. **In Google Cloud Console:**
   - Navigate to: https://console.cloud.google.com/apis/credentials
   - Edit the OAuth 2.0 Client ID
   - Find the NEW secret (created in Part A)
   - Click the trash icon to delete it
   - Click "Save"

2. **On VPS1:**
   ```bash
   # Remove the Docker secret
   docker secret rm oauth_client_secret

   # Revert compose/oauth.yml to use environment variable
   # (See Option 1 above)

   # Restart OAuth
   docker compose up -d oauth
   ```

**The old secret is still in the .env file and will work.**

---

## Post-Rotation Cleanup

**ONLY perform these steps AFTER verifying OAuth works with the new secret.**

### Part F: Remove Old Secret from .env Files

**On your local machine:**

```bash
cd /workspaces/jacker

# Edit .env file
nano .env

# Or use your preferred editor
```

**FIND (around line 32):**

```bash
OAUTH_CLIENT_SECRET=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
```

**REPLACE WITH:**

```bash
# OAuth client secret moved to Docker secret for security
# Create secret on VPS1: echo "secret" | docker secret create oauth_client_secret -
# This value is no longer used by compose/oauth.yml (uses --client-secret-file instead)
OAUTH_CLIENT_SECRET=
```

**Also update .env.defaults:**

```bash
# Edit .env.defaults
nano .env.defaults

# Find line 69:
# OAUTH_CLIENT_SECRET=

# Ensure it's empty (no default value)
# Add comment if desired:
# OAUTH_CLIENT_SECRET=  # Store in Docker secret, not .env
```

**Save both files.**

**Commit the changes:**

```bash
git add .env .env.defaults compose/oauth.yml
git commit -m "security: migrate OAuth client secret to Docker secrets

- Remove OAUTH_CLIENT_SECRET from .env (now using Docker secret)
- Update compose/oauth.yml to use --client-secret-file flag
- Enhances security by removing plaintext secret from git repository
- Follows Docker secrets best practices for credential management

BREAKING CHANGE: VPS1 must have oauth_client_secret Docker secret created
before deploying this change. See docs/OAUTH_SECRET_ROTATION.md for details."

git push origin main
```

---

### Part G: Deploy Updated .env to VPS1

**Copy the sanitized .env file to VPS1:**

```bash
# From local machine
scp .env ubuntu@193.70.40.21:/home/ubuntu/jacker/

# SSH to VPS1 to verify
ssh ubuntu@193.70.40.21

# Check that OAUTH_CLIENT_SECRET is empty or commented
grep "OAUTH_CLIENT_SECRET" /home/ubuntu/jacker/.env

# Expected output:
# OAUTH_CLIENT_SECRET=
# (or)
# # OAUTH_CLIENT_SECRET=

# Restart OAuth to ensure it still works without .env value
cd /home/ubuntu/jacker
docker compose up -d oauth

# Wait and check logs
sleep 10
docker logs oauth --tail 20

# Test OAuth flow one more time
# Navigate to: https://traefik.vps1.jacarsystems.net

exit
```

---

### Part H: Delete Old Secret in Google Cloud Console

**WARNING: Only do this AFTER confirming the new secret works in all tests above!**

1. **Navigate to Google Cloud Console**
   - URL: https://console.cloud.google.com/apis/credentials

2. **Edit OAuth 2.0 Client ID**
   - Click the pencil icon next to your client

3. **Locate Client Secrets Section**
   - You should see TWO secrets listed
   - Old secret: `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`
   - New secret: `GOCSPX-XXXXXXXXXXXXXXXXXXXXXXXXXXXX` (partially hidden)

4. **Delete the OLD Secret**
   - Find the old secret (created before today's date)
   - Click the trash icon (🗑️) next to the old secret
   - Confirm deletion when prompted

5. **Verify Only New Secret Remains**
   - You should now see only ONE client secret
   - This is the new secret you created in Part A

6. **Click "SAVE"**
   - Save the OAuth client configuration

**Checkpoint:** The old exposed secret is now revoked and can no longer be used to authenticate.

---

### Part I: Clean Git History (Optional but HIGHLY Recommended)

**WARNING: This rewrites git history and will affect all users of the repository.**

**Prerequisites:**
- Coordinate with all team members
- Ensure all team members have pushed their changes
- All team members will need to re-clone or reset their local repositories after this operation

**Install git-filter-repo:**

```bash
# On your local machine
# If using Python pip:
pip install git-filter-repo

# Or using apt (Debian/Ubuntu):
sudo apt-get install git-filter-repo

# Or using Homebrew (macOS):
brew install git-filter-repo
```

**Create a final backup:**

```bash
cd /workspaces/jacker

# Create backup branch with current state
git checkout -b backup-before-history-rewrite-$(date +%Y%m%d)
git push origin backup-before-history-rewrite-$(date +%Y%m%d)

# Return to main
git checkout main

# Create a complete backup clone (outside the repository)
cd /workspaces
git clone jacker jacker-backup-$(date +%Y%m%d)
```

**Remove .env from entire git history:**

```bash
cd /workspaces/jacker

# This will remove .env from all commits in history
git filter-repo --path .env --invert-paths --force

# Expected output:
# Parsed X commits
# New history written in X seconds
# ...
```

**Alternative: Remove only the OAUTH_CLIENT_SECRET value from .env (preserves .env file):**

```bash
# This is more complex and requires a custom script
# Recommended: Use the full .env removal above instead
```

**Force push the rewritten history:**

```bash
# WARNING: This is destructive and affects all users
git push --force origin main

# If you have other branches, you may need to force push them too:
# git push --force origin develop
# git push --force origin feature-branch-name
```

**Notify team members:**

Send a message to all team members:

```
URGENT: Git history rewritten for security

The jacker repository history has been rewritten to remove the exposed OAuth client secret.

ACTION REQUIRED:
1. Backup any uncommitted local changes
2. Delete your local jacker repository
3. Re-clone from origin: git clone <repository-url>
4. Re-apply any uncommitted changes

DO NOT merge or pull - you must re-clone.

If you have any questions, contact [your-name] immediately.
```

**Verify history is clean:**

```bash
# Search for the old secret in git history
git log -p --all -S "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"

# Expected output: Nothing (if successful)

# Search in current files
grep -r "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" .

# Expected output: Nothing (or only in this documentation file)
```

---

## Security Best Practices

### 1. Never Commit Secrets to Git

**Use these alternatives:**

- ✅ **Docker Secrets** (for Swarm/Compose) - Current implementation
- ✅ **Environment Variables** (loaded at runtime, not committed)
- ✅ **External Secret Managers** (HashiCorp Vault, AWS Secrets Manager, etc.)
- ✅ **Encrypted Secret Files** (with .gitignore exclusion)
- ❌ **Plaintext in .env files** (never commit .env to git)

**Configure .gitignore:**

```bash
# Verify .env is in .gitignore
cd /workspaces/jacker
grep "^\.env$" .gitignore

# If not present, add it:
echo ".env" >> .gitignore
git add .gitignore
git commit -m "gitignore: ensure .env is never committed"
```

---

### 2. Rotate Secrets Regularly

**Recommended rotation schedule:**

- **OAuth Client Secrets:** Every 90-180 days
- **Database Passwords:** Every 180-365 days
- **API Keys:** Every 90 days
- **TLS Certificates:** Auto-renewed (Let's Encrypt)

**Set calendar reminders:**

- Next OAuth secret rotation: **[90 days from today]**
- Next database password rotation: **[180 days from today]**

---

### 3. Use Service Accounts Where Possible

**Instead of user OAuth (when applicable):**

- Use Google Service Accounts for API access
- Use machine-to-machine authentication (client credentials flow)
- Use API keys with IP restrictions for backend services

**For Jacker:**
- OAuth is necessary for user authentication (correct use case)
- Consider Authentik or Keycloak for more control (future enhancement)

---

### 4. Monitor OAuth Logs for Suspicious Activity

**Set up alerts for:**

- Failed authentication attempts (>10 in 5 minutes)
- OAuth access from unknown IP addresses
- Unusual time-of-day access patterns
- Multiple simultaneous sessions from same user

**Configure Prometheus alerts:**

```bash
# Check if OAuth monitoring is enabled
grep -r "oauth" /workspaces/jacker/config/prometheus/rules/

# If not present, consider adding OAuth-specific alerts
```

---

### 5. Implement IP Allowlisting (If Feasible)

**In Google Cloud Console:**

1. Navigate to OAuth consent screen settings
2. Consider restricting authorized redirect URIs to specific IP ranges
3. Use Cloudflare Access or similar for additional IP-based restrictions

**In Traefik middleware:**

```yaml
# Add IP allowlist to OAuth middleware (if applicable)
# See config/traefik/rules/middlewares-oauth.yml
```

---

### 6. Enable Multi-Factor Authentication (MFA)

**For all Google accounts with access to:**

- Google Cloud Console (project owner/editor roles)
- SSH access to VPS1
- Git repository with admin permissions

**Verify MFA is enabled:**

- https://myaccount.google.com/security
- Check "2-Step Verification" is ON

---

### 7. Regular Security Audits

**Monthly checklist:**

- [ ] Review OAuth access logs for anomalies
- [ ] Check for exposed secrets in git repository
- [ ] Verify all Docker secrets are properly configured
- [ ] Review authorized users in Google OAuth consent screen
- [ ] Update dependencies (OAuth2-Proxy, Traefik, etc.)
- [ ] Test OAuth flow with non-admin account
- [ ] Verify session timeout is appropriate (currently 7 days)

---

## Troubleshooting

### Issue 1: "OAuth2 error: invalid_client"

**Symptoms:**
- Browser shows "OAuth2 error: invalid_client" after clicking "Sign in with Google"
- OAuth logs show: `invalid client secret`

**Causes:**
- New secret doesn't match the one in Google Cloud Console
- Typo when creating Docker secret
- Wrong secret was copied from Google Cloud Console

**Solutions:**

```bash
# Verify the secret in Google Cloud Console (re-generate if needed)

# On VPS1, delete and recreate the Docker secret
docker secret rm oauth_client_secret
echo "CORRECT_NEW_SECRET_HERE" | docker secret create oauth_client_secret -

# Restart OAuth
docker compose up -d oauth

# Test again
```

---

### Issue 2: "Error reading client secret file"

**Symptoms:**
- OAuth fails to start
- Logs show: `error reading client secret file /run/secrets/oauth_client_secret`

**Causes:**
- Docker secret was not created
- Secret name mismatch in compose file
- Secret file is empty

**Solutions:**

```bash
# Check if secret exists
docker secret ls | grep oauth_client_secret

# If not exists, create it
echo "NEW_SECRET_HERE" | docker secret create oauth_client_secret -

# Verify secret is not empty
docker secret inspect oauth_client_secret

# Restart OAuth
docker compose up -d oauth
```

---

### Issue 3: Infinite Redirect Loop

**Symptoms:**
- Browser redirects between OAuth and application endlessly
- Cookies are not being set

**Causes:**
- Cookie domain mismatch
- SameSite cookie policy too restrictive
- Session not being stored in Redis

**Solutions:**

```bash
# Check cookie domain configuration
docker logs oauth | grep -i cookie

# Verify Redis connection
docker exec oauth nc -zv redis 6379

# Check Redis authentication
docker exec oauth redis-cli -h redis -a "${REDIS_OAUTH_PASSWORD}" ping

# Adjust cookie settings in compose/oauth.yml if needed
# - OAUTH2_PROXY_COOKIE_SAMESITE=lax  (try "none" for cross-site)
# - OAUTH2_PROXY_COOKIE_DOMAINS=.${PUBLIC_FQDN}
```

---

### Issue 4: Session Not Persisting

**Symptoms:**
- Must re-authenticate on every browser restart
- Session expires too quickly

**Causes:**
- Redis session store not working
- Cookie expiration too short
- Browser blocking third-party cookies

**Solutions:**

```bash
# Verify Redis session storage
docker exec oauth redis-cli -h redis -a "${REDIS_OAUTH_PASSWORD}" keys "*"

# Should show session keys like: session:XXXXXXXXXXXX

# Check session expiration
docker logs oauth | grep -i session

# Adjust session lifetime in compose/oauth.yml:
# - OAUTH2_PROXY_COOKIE_EXPIRE=604800s  (7 days)
# - OAUTH2_PROXY_COOKIE_REFRESH=3600s   (1 hour)
```

---

### Issue 5: "Failed to connect to Redis"

**Symptoms:**
- OAuth starts but authentication fails
- Logs show: `failed to connect to redis`

**Causes:**
- Redis is not running
- Redis password is incorrect
- Redis network connectivity issue

**Solutions:**

```bash
# Check Redis status
docker ps --filter name=redis

# Check Redis logs
docker logs redis --tail 50

# Verify Redis ACL password
docker exec redis redis-cli ACL GETUSER oauth_user

# Test connection from OAuth container
docker exec oauth nc -zv redis 6379

# Verify redis_oauth_password Docker secret
docker secret inspect redis_oauth_password
```

---

### Issue 6: Git History Cleanup Failed

**Symptoms:**
- `git filter-repo` command fails
- Error: "not a fresh clone"

**Causes:**
- Repository has uncommitted changes
- Repository has unpushed commits
- git-filter-repo safety checks triggered

**Solutions:**

```bash
# Ensure repository is clean
git status

# Commit or stash any changes
git stash

# Ensure all changes are pushed
git push origin main

# Create a fresh clone
cd /workspaces
git clone jacker jacker-fresh
cd jacker-fresh

# Run git-filter-repo on fresh clone
git filter-repo --path .env --invert-paths --force

# Force push
git push --force origin main
```

---

## Verification Checklist

After completing all steps, verify:

- [ ] **New OAuth client secret generated** in Google Cloud Console
- [ ] **Docker secret created** on VPS1 (`docker secret ls | grep oauth_client_secret`)
- [ ] **compose/oauth.yml updated** to use `--client-secret-file` flag
- [ ] **OAuth service restarted** successfully (`docker ps --filter name=oauth`)
- [ ] **OAuth flow tested** and working (can access Traefik dashboard)
- [ ] **Multiple services tested** (Portainer, Grafana, Prometheus)
- [ ] **Session persistence verified** (close/reopen browser, still authenticated)
- [ ] **Old secret removed** from `.env` file
- [ ] **Updated .env deployed** to VPS1
- [ ] **Old secret deleted** from Google Cloud Console (only ONE secret remains)
- [ ] **Git history cleaned** (optional) - old secret no longer in commits
- [ ] **Team notified** of repository changes (if history was rewritten)
- [ ] **Backup branch created** before rotation
- [ ] **Documentation updated** with rotation date (update line 12 of this file)
- [ ] **Calendar reminder set** for next rotation (90 days from today)

---

## Success Criteria

**This rotation is complete when:**

1. ✅ OAuth authentication works with the new secret
2. ✅ All protected services are accessible via OAuth
3. ✅ Sessions persist across browser restarts
4. ✅ No errors in OAuth logs related to client secret
5. ✅ Old secret is removed from all `.env` files
6. ✅ Old secret is revoked in Google Cloud Console
7. ✅ (Optional) Git history is clean of the old secret
8. ✅ Team members are notified and have re-cloned (if history was rewritten)

---

## Additional Resources

**OAuth2-Proxy Documentation:**
- Official docs: https://oauth2-proxy.github.io/oauth2-proxy/
- Configuration: https://oauth2-proxy.github.io/oauth2-proxy/docs/configuration/overview
- Google provider: https://oauth2-proxy.github.io/oauth2-proxy/docs/configuration/oauth_provider#google-auth-provider

**Google Cloud Console:**
- OAuth credentials: https://console.cloud.google.com/apis/credentials
- OAuth consent screen: https://console.cloud.google.com/apis/credentials/consent

**Docker Secrets:**
- Documentation: https://docs.docker.com/engine/swarm/secrets/
- Best practices: https://docs.docker.com/compose/use-secrets/

**Git History Cleanup:**
- git-filter-repo: https://github.com/newren/git-filter-repo
- BFG Repo-Cleaner (alternative): https://rtyley.github.io/bfg-repo-cleaner/

**Jacker Documentation:**
- Deployment guide: `/workspaces/jacker/docs/DEPLOYMENT_GUIDE.md`
- Troubleshooting: `/workspaces/jacker/docs/TROUBLESHOOTING.md`
- OAuth middleware config: `/workspaces/jacker/config/traefik/rules/middlewares-oauth.yml`

---

## Contact & Support

**If you encounter issues during this rotation:**

1. **DO NOT PANIC** - The old secret is still valid until you delete it in Part H
2. **CHECK LOGS** - Most issues are visible in OAuth logs: `docker logs oauth --tail 100`
3. **ROLLBACK IF NEEDED** - Use the rollback procedure above to restore working state
4. **DOCUMENT THE ISSUE** - Note what went wrong for future reference
5. **SEEK HELP** - Reach out to team members or OAuth2-Proxy community

**Emergency Rollback:**
If OAuth is completely broken and you need immediate access to services:

```bash
# Temporarily disable OAuth on a specific service
# Edit the service's compose file and remove the OAuth middleware
# Example for Traefik:
# Change: middlewares=chain-oauth@file
# To:     middlewares=chain-no-oauth@file

# Restart the service
docker compose up -d traefik

# Access the service directly (no authentication required temporarily)
# FIX OAUTH IMMEDIATELY - DO NOT LEAVE IN THIS STATE
```

---

**Document Version:** 1.0
**Last Updated:** 2025-10-18
**Next Review:** 2025-11-18 (30 days)
**Rotation Performed:** [DATE TO BE FILLED IN AFTER COMPLETION]
**Performed By:** [YOUR NAME]

---

## Appendix A: Understanding Docker Secrets

**What are Docker Secrets?**

Docker secrets provide a secure way to store sensitive information (passwords, API keys, certificates) and make them available to containers at runtime without exposing them in:
- Dockerfile
- docker-compose.yml
- Environment variables (visible in `docker inspect`)
- Process listings

**How Docker Secrets Work:**

1. **Creation:** Secret is created and encrypted in Docker's internal database
   ```bash
   echo "my-secret-value" | docker secret create my_secret -
   ```

2. **Reference:** Compose file references the secret by name
   ```yaml
   secrets:
     - my_secret
   ```

3. **Mount:** Docker mounts the secret as a read-only file in the container at `/run/secrets/my_secret`

4. **Access:** Application reads the file to retrieve the secret value
   ```bash
   cat /run/secrets/my_secret
   ```

**Security Benefits:**

- ✅ Secrets are encrypted at rest
- ✅ Secrets are only available to authorized containers
- ✅ Secrets are never logged or visible in `docker inspect`
- ✅ Secrets are not stored in image layers
- ✅ Secrets can be rotated without rebuilding images

**Limitations:**

- ⚠️ Requires Docker Swarm mode or Compose v3.1+ (Jacker uses Compose v3.8)
- ⚠️ Secrets are still visible to root user inside the container
- ⚠️ Not encrypted in transit (use TLS for network transmission)

**For Jacker:**

Current secrets in use:
- `oauth_client_secret` - Google OAuth client secret
- `oauth_cookie_secret` - OAuth session encryption key
- `redis_oauth_password` - Redis ACL password for OAuth user

---

## Appendix B: OAuth2-Proxy Configuration Precedence

**OAuth2-Proxy loads configuration from multiple sources in this order (lowest to highest priority):**

1. **Configuration file** (`/etc/oauth2-proxy/oauth2-proxy.cfg`)
   - Base configuration
   - Default values

2. **Environment variables** (e.g., `OAUTH2_PROXY_CLIENT_SECRET`)
   - Overrides config file values
   - Previously used method (INSECURE)

3. **Command-line flags** (e.g., `--client-secret-file=/run/secrets/oauth_client_secret`)
   - Overrides both config file and environment variables
   - **Current method (SECURE)**

**This means:**
- Even if `OAUTH2_PROXY_CLIENT_SECRET` is set in environment, the `--client-secret-file` flag takes precedence
- The config file's `client_secret = "${OAUTH_CLIENT_SECRET}"` is ignored when using the command-line flag
- Removing the environment variable is for security hygiene, not functional necessity

**Verification:**

```bash
# OAuth2-Proxy will log which configuration source it's using
docker logs oauth 2>&1 | grep -i "client.*secret"

# No output = using secret file correctly (not logged for security)
# Error message = problem with secret file, check configuration
```

---

## Appendix C: Redis Session Storage

**Why Redis for OAuth Sessions?**

Jacker uses Redis for OAuth session storage instead of cookie-based sessions for these benefits:

1. **Scalability** - Can distribute sessions across multiple OAuth containers
2. **Security** - Session data stored server-side, not in client cookies
3. **Size** - No cookie size limitations (4KB limit for cookies)
4. **Control** - Can revoke sessions by deleting Redis keys
5. **Persistence** - Sessions survive OAuth container restarts

**Redis ACL Configuration:**

OAuth2-Proxy uses a dedicated Redis user (`oauth_user`) with limited permissions:

```redis
user oauth_user on >PASSWORD ~session:* &* +get +set +del +expire +ttl
```

Permissions breakdown:
- `on` - User is enabled
- `>PASSWORD` - User password (from `redis_oauth_password` secret)
- `~session:*` - Only access keys matching `session:*` pattern
- `&*` - Can access all pub/sub channels
- `+get +set +del +expire +ttl` - Allowed commands only

**Session Key Format:**

```
session:XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

Where `XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX` is the session ID (stored in `_oauth2_proxy` cookie).

**Session Lifecycle:**

1. User authenticates via Google OAuth
2. OAuth2-Proxy creates session ID and stores session data in Redis
3. Session ID is set in `_oauth2_proxy` cookie (encrypted)
4. On subsequent requests, OAuth2-Proxy reads session ID from cookie and retrieves session data from Redis
5. Session expires after `OAUTH2_PROXY_COOKIE_EXPIRE` (7 days by default)
6. Redis automatically deletes expired sessions (TTL-based eviction)

**Troubleshooting Session Issues:**

```bash
# List all sessions in Redis
docker exec redis redis-cli -a "${REDIS_OAUTH_PASSWORD}" --user oauth_user keys "session:*"

# Check session TTL (time to live)
docker exec redis redis-cli -a "${REDIS_OAUTH_PASSWORD}" --user oauth_user TTL session:XXXXX

# Manually delete a session (force logout)
docker exec redis redis-cli -a "${REDIS_OAUTH_PASSWORD}" --user oauth_user DEL session:XXXXX

# Count total sessions
docker exec redis redis-cli -a "${REDIS_OAUTH_PASSWORD}" --user oauth_user keys "session:*" | wc -l
```

---

**END OF DOCUMENT**
