# FRIDAY - FREE TIER DEPLOYMENT GUIDE

Zero-cost deployment for FRIDAY AI Security Scanner.

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Cloudflare (Free)                        │
│  ┌──────────────────┐        ┌──────────────────────────┐  │
│  │  friday.openclaw.dev    │        │  api.friday.openclaw.dev      │  │
│  │  (Cloudflare Pages)     │───────→│  (Render Free)              │  │
│  │  • Always fast          │        │  • Sleeps after 15min       │  │
│  │  • Global CDN           │        │  • Cold start: ~30-60s      │  │
│  │  • friday.sh served     │        │  • SQLite on disk           │  │
│  └──────────────────┘        └──────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## 💰 Cost Breakdown

| Service | Plan | Cost |
|---------|------|------|
| Cloudflare Pages | Free | $0 |
| Render Web Service | Free | $0 |
| Render Disk (1GB) | Free tier | $0 |
| Cloudflare DNS | Free | $0 |
| **TOTAL** | | **$0/month** |

## ⚠️ COLD START BEHAVIOR

### What is Cold Start?

Render Free tier **spins down** the API service after **15 minutes of inactivity**:

```
Active:    API responds instantly (< 100ms)
           ↑
Idle:      No requests for 15 minutes
           ↓
Sleep:     Service spun down (0ms response)
           ↓
Wake:      First request triggers cold start (~30-60 seconds)
           ↓
Active:    Service warm again (normal response times)
```

### Impact

| Endpoint | Impact | Mitigation |
|----------|--------|------------|
| `friday.sh` | **None** | Served by Cloudflare Pages (always fast) |
| `/api/health` | 30-60s delay | UptimeRobot ping every 14 min keeps warm |
| `/api/leaderboard` | 30-60s delay | User sees loading state |
| `/api/leaderboard/submit` | 30-60s delay | Retry logic in friday.sh script |

### Keeping the API Warm (Optional)

**Free solution - UptimeRobot:**
1. Sign up at [uptimerobot.com](https://uptimerobot.com) (free)
2. Add monitor:
   - Type: HTTP(s)
   - URL: `https://api.friday.openclaw.dev/api/health`
   - Interval: 14 minutes (keeps under 15min threshold)
3. Result: API stays warm 24/7

**Cost if kept warm:** Still $0 (within free tier limits)

## 🚀 Deployment Steps

### Step 1: Fork/Create Repository

```bash
# Create new GitHub repository for FRIDAY
git init friday-deployment
cd friday-deployment

# Copy deployment files
cp /path/to/friday/render.yaml .
cp /path/to/friday/server.js .
cp /path/to/friday/package.json .
cp /path/to/friday/scripts/backup-render.js ./scripts/
cp /path/to/friday/.env.example .
cp /path/to/friday/public ./ -r

# Commit
git add .
git commit -m "Initial FRIDAY deployment"
git push origin main
```

### Step 2: Deploy API to Render

1. Go to [Render Dashboard](https://dashboard.render.com/)
2. Click **New +** → **Blueprint**
3. Connect your GitHub repository
4. Render creates:
   - `friday-api` web service (Node.js)
   - `friday-data` disk (1GB SQLite storage)
   - `friday-backup` cron job (every 6 hours)
5. Wait for deployment (green checkmark)

**Note the API URL:** `https://friday-api-xxxxx.onrender.com`

### Step 3: Configure Environment Variables

In Render Dashboard → friday-api → Environment:

```bash
ADMIN_TOKEN=your-secure-random-token-here
API_KEY=your-api-key-for-external-access
ENABLE_LEADERBOARD=true
ENABLE_PUBLIC_STATS=true
CORS_ORIGINS=https://friday.openclaw.dev,https://*.pages.dev
```

Generate tokens:
```bash
openssl rand -base64 32
```

### Step 4: Set Up Cloudflare Pages

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com/)
2. **Pages** → **Create a project**
3. Connect to GitHub repository
4. Build settings:
   - Build command: `mkdir -p build && cp public/friday.sh build/ && echo '<!DOCTYPE html><html><head><meta http-equiv="refresh" content="0; url=./friday.sh"></head><body>Redirecting...</body></html>' > build/index.html`
   - Build output directory: `build`
5. Deploy

**Note the Pages URL:** `https://friday-xxxxx.pages.dev`

### Step 5: Configure DNS

**Cloudflare Dashboard → DNS → Records:**

```
Type:    CNAME
Name:    friday
Target:  friday-xxxxx.pages.dev  (from Cloudflare Pages)
TTL:     Auto
Proxy:   Proxied (orange cloud) ✅
```

```
Type:    CNAME
Name:    api.friday
Target:  friday-api-xxxxx.onrender.com  (from Render)
TTL:     Auto
Proxy:   DNS only (gray cloud) ⚠️ REQUIRED
```

**Why api.friday must be DNS only:**
- Render handles its own SSL certificates
- Cloudflare proxy causes SSL handshake issues with Render Free tier
- Gray cloud = DNS only, no proxy

### Step 6: GitHub Actions (Auto-Deploy)

The included `.github/workflows/deploy-cf-pages.yml` automatically deploys to Cloudflare Pages on every push.

**Required GitHub Secrets:**
- `CLOUDFLARE_API_TOKEN` - Create at [dash.cloudflare.com/profile/api-tokens](https://dash.cloudflare.com/profile/api-tokens)
  - Permissions: `Zone:Read`, `Page Rules:Edit`, `Cloudflare Pages:Edit`
  - Zone Resources: Include your zone (openclaw.dev)
- `CLOUDFLARE_ACCOUNT_ID` - Found on Cloudflare dashboard right sidebar
- `CLOUDFLARE_ZONE_ID` - Found on Cloudflare dashboard right sidebar

## 📊 Monitoring

### Health Endpoints

```bash
# API health (may be slow if cold)
curl https://api.friday.openclaw.dev/api/health

# Expected response when warm:
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00Z",
  "version": "1.0.0",
  "database": "connected",
  "uptime": 3600,
  "coldStart": false
}

# Expected response when cold:
# (30-60 second delay, then same response with "coldStart": true)
```

### Check if API is Warm

```bash
# Quick check
curl -s -o /dev/null -w "%{time_total}" https://api.friday.openclaw.dev/api/health

# Results:
# < 1 second = Warm ✅
# 30-60 seconds = Cold start ⚠️
```

### UptimeRobot Setup (Keeps Warm)

1. [uptimerobot.com](https://uptimerobot.com) → Sign up (free)
2. **Add New Monitor**:
   - Monitor Type: HTTP(s)
   - Friendly Name: FRIDAY API
   - URL: `https://api.friday.openclaw.dev/api/health`
   - Monitoring Interval: 14 minutes (840 seconds)
3. **Alert Contacts** (optional):
   - Email: your-email@example.com
   - Discord webhook for downtime alerts

## 💾 Backup Strategy

### Automatic Backups (Render Cron Job)

- **Frequency:** Every 6 hours
- **Storage:** Local (7-day retention) + S3 (if configured)
- **Location:** `/opt/render/project/src/data/`

### Manual Backup

```bash
# Via admin API endpoint
curl -H "Authorization: Bearer $ADMIN_TOKEN" \
  https://api.friday.openclaw.dev/api/admin/backup \
  -o friday-backup.db
```

### Database Persistence Notes

✅ **Survives:**
- Service restarts
- Brief outages
- Code deployments (if disk attached)

❌ **Does NOT survive:**
- Manual disk deletion
- Service deletion
- Account deletion
- Render infrastructure issues

**Mitigation:** Regular backups to S3 (configure in render.yaml env vars)

## 🔧 Troubleshooting

### "Service Unavailable" on API

**Cause:** Service sleeping (cold start in progress)

**Fix:**
1. Wait 30-60 seconds
2. Or set up UptimeRobot to keep warm

### DNS Not Resolving

```bash
# Check CNAME records
dig CNAME friday.openclaw.dev +short
dig CNAME api.friday.openclaw.dev +short

# Should return:
# friday-xxxxx.pages.dev
# friday-api-xxxxx.onrender.com
```

### SSL Certificate Errors

**Symptom:** `curl: (60) SSL certificate problem`

**Fix:**
1. Ensure `api.friday` is **DNS only** (gray cloud)
2. Wait 5 minutes for SSL provisioning
3. Check Render Dashboard → friday-api → Settings → Custom Domains

### Script Download Fails

```bash
# Test direct download
curl -I https://friday.openclaw.dev/friday.sh

# Should show:
# HTTP/2 200
# content-type: text/plain; charset=utf-8
# cache-control: no-cache
```

### Database Locked Errors

**Cause:** Concurrent writes to SQLite

**Fix:** Already handled by WAL mode, but if persists:
1. Check Render Dashboard → Logs
2. Restart service if needed
3. Consider upgrading to Render Starter ($7/month) for PostgreSQL

## 📈 Scaling Path

If you outgrow free tier:

| Current | Upgrade | Cost | Benefit |
|---------|---------|------|---------|
| Render Free | Render Starter | $7/mo | No cold starts, more RAM |
| SQLite | Render PostgreSQL | $7/mo | Better concurrency, backups |
| CF Pages Free | CF Pro | $20/mo | More features, analytics |

## ✅ Deployment Checklist

- [ ] Repository pushed to GitHub
- [ ] Render Blueprint deployed
- [ ] Environment variables set
- [ ] Cloudflare Pages created
- [ ] DNS records added (friday + api.friday)
- [ ] SSL certificates active
- [ ] Script download test passes
- [ ] API health check responds
- [ ] Leaderboard submission works
- [ ] UptimeRobot configured (optional)
- [ ] Backup job running

## 📝 Summary

| Component | Provider | Behavior | Cost |
|-----------|----------|----------|------|
| Static Site (friday.sh) | Cloudflare Pages | Always fast, global CDN | Free |
| API (leaderboard) | Render Free | Sleeps after 15min, cold start ~30-60s | Free |
| Database | SQLite on Render Disk | Persists across restarts | Free |
| Backups | Render Cron + S3 | Every 6 hours | Free* |
| DNS | Cloudflare | Fast propagation | Free |
| SSL | Cloudflare + Let's Encrypt | Auto-renew | Free |

*S3 storage costs may apply if using AWS backups (~$0.023/GB/month)

**Total: $0/month** 🎉

---

**Questions?** See `DNS-SETUP.md` for detailed DNS configuration or `README.md` for general architecture.
