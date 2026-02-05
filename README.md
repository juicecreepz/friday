# FRIDAY

🛡️ Security hardening tool for OpenClaw AI assistants. One command to audit vulnerabilities, detect malicious skills via Clawdex, and secure your instance.

```bash
curl -sSL friday.openclaw.dev | bash
```

[![GitHub stars](https://img.shields.io/github/stars/juicecreepz/friday?style=social)](https://github.com/juicecreepz/friday)
[![Twitter Follow](https://img.shields.io/twitter/follow/juicetin?style=social)](https://twitter.com/juicetin)

---

## 🚀 Quick Start

```bash
curl -sSL friday.openclaw.dev | bash
```

## ✨ Features

- **One-Command Audit** - No dependencies, no sign-up required
- **Malicious Skill Detection** - Real-time checks against Clawdex database for malicious and unknown skills
- **Armor Rating** - 5 vectors: Network, Permissions, Gateway, Channels, Skills
- **Auto-Fix** - Automatically hardens firewall, permissions, and gateway binding
- **Tailscale Integration** - Optional upgrade for private mesh networking
- **Global Leaderboard** - Compare ratings worldwide (opt-in)
- **Gamified** - Stark Certified badges and achievements

## 🏆 Security Scores

| Score | Badge | Status |
|----|----|----|
| 90-100 | ★ Stark Certified ★ | Excellent |
| 70-89 | ◆ Shield Protocol Active ◆ | Good |
| 50-69 | ⚠ Suit Damage Detected | Needs Work |
| <50 | 🚨 Critical Failure | Immediate Action Required |

## 📊 What FRIDAY Checks

1. **Network (30 pts)** - Tailscale, firewall, SSH exposure
2. **Permissions (25 pts)** - File permissions, config exposure
3. **Gateway (25 pts)** - Bind address, auth tokens
4. **Channels (20 pts)** - Group policies, allowlists
5. **Skills (20 pts)** - Clawdex verification for malicious/unknown skills

## 🛠️ Self-Hosting

Want to run your own FRIDAY instance? See [DEPLOY.md](DEPLOY.md) for detailed deployment instructions including Render, Docker, and manual setup.

## 🙏 Credits

- Built by [@juicetin](https://twitter.com/juicetin)
- Malicious skill detection powered by [Clawdex](https://clawdex.koi.security) (Koi Security)
- Inspired by the OpenClaw community

---

*"Sir, I have indeed been uploaded."* - FRIDAY

## 📜 License

MIT License - see [LICENSE](LICENSE) file
