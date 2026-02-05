# DNS Setup for FREE TIER Stack

DNS configuration for `friday.openclaw.dev` using Cloudflare Pages + Render Free.

## Architecture

```
User Request:
├── friday.openclaw.dev → Cloudflare Pages (always fast)
└── api.friday.openclaw.dev → Render Free (may cold start)
```

## DNS Records

### Required Records

| Type | Name | Target | Proxy Status | TTL |
|------|------|--------|--------------|-----|
| CNAME | friday | `xxx.pages.dev` | **Proxied** (orange 🟠) | Auto |
| CNAME | api.friday | `xxx.onrender.com` | **DNS only** (gray ⚪) | Auto |

### Step-by-Step Setup

#### 1. Get Your URLs

**After Cloudflare Pages Deploy:**
- Go to Cloudflare Dashboard → Pages → friday
- Copy the URL: `https://friday-abc123.pages.dev`

**After Render Deploy:**
- Go to Render Dashboard → friday-api → Settings
- Copy the URL: `https://friday-api-xyz789.onrender.com`

#### 2. Add DNS Records in Cloudflare

**Cloudflare Dashboard → Select Domain (openclaw.dev) → DNS → Records**

**Record 1 - Main Domain (Cloudflare Pages):**
```
Type: CNAME
Name: friday
IPv4 address: friday-abc123.pages.dev  ← Your Pages URL
Proxy status: Proxied (orange cloud)
TTL: Auto
```

**Record 2 - API Subdomain (Render):**
```
Type: CNAME
Name: api.friday
Target: friday-api-xyz789.onrender.com  ← Your Render URL
Proxy status: DNS only (gray cloud) ⚠️ IMPORTANT
TTL: Auto
```

⚠️ **CRITICAL:** `api.friday` MUST be "DNS only" (gray cloud). 
If proxied (orange), SSL handshake will fail between Cloudflare and Render.

#### 3. Configure Cloudflare Pages Custom Domain

1. Cloudflare Dashboard → Pages → friday → Custom domains
2. Click **Set up a custom domain**
3. Enter: `friday.openclaw.dev`
4. Cloudflare automatically adds the CNAME and provisions SSL
5. Wait for "Active" status (usually 1-2 minutes)

#### 4. Configure Render Custom Domain

1. Render Dashboard → friday-api → Settings → Custom Domains
2. Click **Add Custom Domain**
3. Enter: `api.friday.openclaw.dev`
4. Click **Verify**
5. Wait for SSL certificate provisioning (1-5 minutes)
6. Status should show "Valid"

### SSL/TLS Configuration

**Cloudflare Dashboard → SSL/TLS → Overview**

```
Encryption mode: Full (strict)
```

**Edge Certificates:**
```
Always Use HTTPS: ON
Automatic HTTPS Rewrites: ON
Minimum TLS Version: 1.2
```

### Caching Configuration

**Cloudflare Dashboard → Caching → Configuration**

```
Caching Level: Standard
Browser Cache TTL: 30 minutes
Crawler Hints: ON
```

**Page Rules (Free tier: 3 rules):**

```
URL: friday.openclaw.dev/friday.sh
Settings:
  - Browser Cache TTL: 5 minutes
  - Edge Cache TTL: 5 minutes
  - Cache Level: Cache Everything

URL: api.friday.openclaw.dev/*
Settings:
  - Browser Cache TTL: 0 seconds (no cache for API)
  - Disable Performance: true
```

## Verification

### Test DNS Resolution

```bash
# Check friday.openclaw.dev
dig friday.openclaw.dev +short
# Expected: 104.16.XXX.XXX (Cloudflare IP - proxied)

# Check api.friday.openclaw.dev
dig api.friday.openclaw.dev +short
# Expected: friday-api-xxx.onrender.com (CNAME, not proxied)
```

### Test Script Download

```bash
# Test with verbose output
curl -v https://friday.openclaw.dev/friday.sh 2>&1 | head -20

# Should show:
# Connected to friday.openclaw.dev (104.16.XXX.XXX)
# HTTP/2 200
# content-type: text/plain; charset=utf-8
```

### Test API

```bash
# Health check (may be slow if cold)
curl -w "@curl-format.txt" https://api.friday.openclaw.dev/api/health

# Create curl-format.txt:
# time_namelookup: %{time_namelookup}\n
# time_connect: %{time_connect}\n
# time_appconnect: %{time_appconnect}\n
# time_pretransfer: %{time_pretransfer}\n
# time_redirect: %{time_redirect}\n
# time_starttransfer: %{time_starttransfer}\n
# time_total: %{time_total}\n
```

## Troubleshooting

### "SSL handshake failed" on API

**Cause:** api.friday is proxied (orange cloud)

**Fix:**
1. Cloudflare DNS → api.friday record
2. Toggle to **DNS only** (gray cloud)
3. Wait 1-2 minutes
4. Test again

### "Too many redirects" on main domain

**Cause:** SSL mode is "Flexible"

**Fix:**
1. Cloudflare SSL/TLS → Overview
2. Change to **Full (strict)**

### Domain not resolving after 1 hour

**Check:**
```bash
# Verify CNAME exists
dig CNAME friday.openclaw.dev +short

# Check global propagation
for ns in 1.1.1.1 8.8.8.8 9.9.9.9; do
    echo "=== $ns ==="
    dig @$ns friday.openclaw.dev +short
done
```

### Render domain verification fails

**Common causes:**
1. CNAME target mismatch (copy-paste error)
2. DNS propagation delay (wait 5-10 min)
3. Cloudflare proxy interfering (ensure DNS only for api)

**Fix:**
```bash
# Verify exact CNAME
dig CNAME api.friday.openclaw.dev +short
# Should exactly match your Render URL
```

## GitHub Pages Alternative

If you prefer GitHub Pages over Cloudflare Pages:

### DNS Changes

```
Type: CNAME
Name: friday
Target: yourusername.github.io
Proxy: DNS only (gray) or Proxied (orange)
```

### GitHub Settings

1. Repository → Settings → Pages
2. Source: Deploy from branch (main)
3. Folder: / (root)
4. Custom domain: `friday.openclaw.dev`
5. Enforce HTTPS: ON

**Trade-offs:**
- ✅ GitHub Pages: Simpler setup, built-in CI
- ✅ Cloudflare Pages: Faster global CDN, better caching
- ❌ GitHub Pages: 100GB/month bandwidth limit
- ❌ Cloudflare Pages: Unlimited bandwidth

## Summary

| Domain | Provider | Proxy | SSL |
|--------|----------|-------|-----|
| friday.openclaw.dev | Cloudflare Pages | **Orange** (Proxied) | Cloudflare |
| api.friday.openclaw.dev | Render | **Gray** (DNS only) | Let's Encrypt |

**Remember:**
- 🟠 Orange cloud = Cloudflare proxy (good for static site)
- ⚪ Gray cloud = DNS only (required for Render API)
