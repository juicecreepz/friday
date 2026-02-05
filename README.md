# FRIDAY

🛡️ One-command security auditor for OpenClaw AI assistants. Named after Tony Stark's AI. Scores your security, detects malicious skills via Clawdex, and ranks you on a global leaderboard. 

```bash
curl -sSL friday.openclaw.dev | bash
```

[![GitHub stars](https://img.shields.io/github/stars/juicecreepz/friday?style=social)](https://github.com/juicecreepz/friday)
[![Twitter Follow](https://img.shields.io/twitter/follow/juicetin?style=social)](https://twitter.com/juicetin)

---

Everyone names their OpenClaw "Jarvis" - but who's protecting Jarvis? 

FRIDAY is a security-first audit tool that scans your AI assistant for vulnerabilities, malicious skills, and network exposure. Get your Stark Certified security score and climb the global leaderboard.

## 🚀 Quick Start

```bash
curl -sSL friday.openclaw.dev | bash
```

## ✨ Features

- **One-Command Audit** - No dependencies, no sign-up
- **Malicious Skill Detection** - Checks against Clawdex database (detected 341 malicious skills in ClawHavoc attack)
- **Security Scoring** - 5 vectors: Network, Permissions, Gateway, Channels, Skills
- **Auto-Fix** - Automatically hardens firewall, permissions, and gateway binding
- **Tailscale Integration** - Optional upgrade for private mesh networking
- **Global Leaderboard** - Compare scores worldwide (opt-in)
- **Gamified** - Stark Certified badges and achievements

## 🏆 Security Scores

| Score | Badge | Status |
|----|----|----|
| 90-100 | ★ Stark Certified ★ | Excellent |
| 70-89 | ◆ Shield Protocol Active ◆ | Good |
| 50-69 | ⚠ Suit Damage Detected | Needs Work |
| <50 | 🚨 Critical | Immediate Action Required |

## 📊 What FRIDAY Checks

1. **Network (30 pts)** - Tailscale, firewall, SSH exposure
2. **Permissions (25 pts)** - File permissions, config exposure
3. **Gateway (25 pts)** - Bind address, auth tokens
4. **Channels (20 pts)** - Group policies, allowlists
5. **Skills (20 pts)** - Clawdex verification for malicious/unknown skills

## 🛠️ Self-Hosting

### Deploy Backend
```bash
cd friday-api
npm install
npm start
```

### Deploy Frontend
Static hosting (GitHub Pages, Cloudflare Pages, etc.):
```bash
cd friday-frontend
# Upload to your static host
```

### Render (One-Click)
[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy)

## 🙏 Credits

- Built by [@juicetin](https://twitter.com/juicetin)
- Malicious skill detection powered by [Clawdex](https://clawdex.koi.security) (Koi Security)
- Inspired by the OpenClaw community

## 📜 License

MIT License - see [LICENSE](LICENSE) file
