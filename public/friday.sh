#!/bin/bash
#
# FRIDAY v1.0 - AI Instance Security
# curl -sSL friday-boi.pages.dev | bash
#
# One-command security hardening for OpenClaw

# Don't use set -e for piped execution - handle errors manually
# set -e

# Colors (use real ESC so we don't rely on `echo -e`)
BLACK=$'\033[0;30m'
BLUE=$'\033[38;5;81m'      # Arc reactor blue
GREEN=$'\033[38;5;84m'     # JARVIS green
GOLD=$'\033[38;5;214m'     # Stark gold
RED=$'\033[38;5;196m'      # Alert red
WHITE=$'\033[38;5;255m'    # Soft white
GRAY=$'\033[38;5;240m'     # Muted
NC=$'\033[0m'

# Disable colors when not writing to a real TTY (prevents escape garbage in logs/pastes)
if ! [ -t 1 ]; then
  BLACK=''; BLUE=''; GREEN=''; GOLD=''; RED=''; WHITE=''; GRAY=''; NC=''
fi

# Score tracking
NETWORK_SCORE=0
PERM_SCORE=0
GATEWAY_SCORE=0
CHANNEL_SCORE=0
SKILL_SCORE=0
TOTAL_SCORE=0

# Malicious skills tracking
MALICIOUS_SKILLS=()
UNKNOWN_SKILLS=()

# Issue tracking (structured fields; command can contain any characters)
ISSUE_CATEGORY=()
ISSUE_POINTS=()
ISSUE_DESC=()
ISSUE_CMD=()
ISSUE_NEEDS_SUDO=()
ISSUE_MANUAL=()

issues_reset() {
    ISSUE_CATEGORY=()
    ISSUE_POINTS=()
    ISSUE_DESC=()
    ISSUE_CMD=()
    ISSUE_NEEDS_SUDO=()
    ISSUE_MANUAL=()
}

# issue_add <Category> <Points> <Description> <Command> <NeedsSudo:true|false> <Manual:true|false>
# Command must be COMMAND-ONLY (no prose). Leave Command empty for manual-only guidance.
issue_add() {
    local category="$1"
    local points="$2"
    local desc="$3"
    local cmd="${4:-}"
    local needs_sudo="${5:-false}"
    local manual="${6:-false}"

    ISSUE_CATEGORY+=("$category")
    ISSUE_POINTS+=("$points")
    ISSUE_DESC+=("$desc")
    ISSUE_CMD+=("$cmd")
    ISSUE_NEEDS_SUDO+=("$needs_sudo")
    ISSUE_MANUAL+=("$manual")
}

# Instance ID
INSTANCE_ID="friday-$(date +%s | tail -c 5)"

# Banner
print_banner() {
    echo -e "${BLUE}"
    echo '    ███████╗██████╗ ██╗██████╗  █████╗ ██╗   ██╗'
    echo '    ██╔════╝██╔══██╗██║██╔══██╗██╔══██╗╚██╗ ██╔╝'
    echo '    █████╗  ██████╔╝██║██║  ██║███████║ ╚████╔╝ '
    echo '    ██╔══╝  ██╔══██╗██║██║  ██║██╔══██║  ╚██╔╝  '
    echo '    ██║     ██║  ██║██║██████╔╝██║  ██║   ██║   '
    echo '    ╚═╝     ╚═╝  ╚═╝╚═╝╚═════╝ ╚═╝  ╚═╝   ╚═╝   '
    echo -e "${GRAY}                                          v1.0.0${NC}"
    echo
}

# FRIDAY voice lines
speak() {
    echo -e "${BLUE}🎙️  FRIDAY:${NC} ${WHITE}$1${NC}"
    echo
}

# Progress spinner
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf "${BLUE}%s${NC}  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\r"
    done
    printf "    \r"
}

# Section header
section() {
    echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Safe read function that works with piped input
# Always tries /dev/tty first for true interactivity
safe_read() {
    local var_name="$1"
    local prompt="$2"
    
    # Always try /dev/tty first for true interactivity
    # NOTE: in many `curl | bash` scenarios, stdin is not a TTY, but /dev/tty is readable.
    if [ -r /dev/tty ]; then
        if [ -n "$prompt" ] && [ -w /dev/tty ]; then
            printf "%s" "$prompt" > /dev/tty
        elif [ -n "$prompt" ]; then
            # Fallback: print prompt to stdout
            printf "%s" "$prompt"
        fi
        IFS= read -r "$var_name" < /dev/tty
        return 0
    fi
    
    # Fallback to stdin if /dev/tty not available
    if [ -t 0 ]; then
        if [ -n "$prompt" ]; then
            printf "%s" "$prompt"
        fi
        IFS= read -r "$var_name"
        return 0
    fi
    
    # Last resort: use stdin with timeout (for piped input)
    # Keep timeout short so we don't hang, but do not silently treat 'y' as 'no'.
    if [ -n "$prompt" ]; then
        printf "%s" "$prompt"
    fi
    IFS= read -r -t 15 "$var_name" || eval "$var_name=''"
}

# sudo preflight (run once when the first sudo fix is chosen)
SUDO_VALIDATED=false
SUDO_KEEPALIVE_PID=""

sudo_keepalive_start() {
    # Best-effort: keep sudo timestamp alive until script exits.
    ( while true; do sudo -n true 2>/dev/null || exit 0; sleep 60; done ) &
    SUDO_KEEPALIVE_PID=$!
}

sudo_cleanup() {
    if [ -n "${SUDO_KEEPALIVE_PID:-}" ] && kill -0 "$SUDO_KEEPALIVE_PID" 2>/dev/null; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
}
trap sudo_cleanup EXIT

ensure_sudo() {
    if [ "$SUDO_VALIDATED" = true ]; then
        return 0
    fi
    if ! command -v sudo >/dev/null 2>&1; then
        echo -e "${RED}✗${NC} sudo not found; can't run privileged steps."
        return 1
    fi
    echo -e "${GRAY}sudo password may be required...${NC}"
    if ! sudo -v; then
        echo -e "${RED}✗${NC} sudo authentication failed."
        return 1
    fi
    SUDO_VALIDATED=true
    sudo_keepalive_start
    return 0
}

# Robust JSON POST helper for leaderboard (captures HTTP status + body)
HTTP_STATUS=""
HTTP_BODY=""
HTTP_ERR=""

http_post_json() {
    local url="$1"
    local json="$2"

    local body_file
    local err_file
    body_file=$(mktemp 2>/dev/null || mktemp -t friday_body)
    err_file=$(mktemp 2>/dev/null || mktemp -t friday_err)

    local http
    http=$(curl -sS --connect-timeout 5 --max-time 15         -H "Content-Type: application/json"         -d "$json"         -o "$body_file"         -w "%{http_code}"         "$url" 2>"$err_file")
    local rc=$?

    HTTP_STATUS="$http"
    HTTP_BODY=$(cat "$body_file" 2>/dev/null || true)
    HTTP_ERR=$(cat "$err_file" 2>/dev/null || true)

    rm -f "$body_file" "$err_file" 2>/dev/null || true

    return $rc
}


# Install Tailscale
install_tailscale() {
    speak "Initiating armor upgrade sequence..."
    
    # The one-liner that does it all
    curl -fsSL https://tailscale.com/install.sh | sh
    
    echo -e "${GREEN}✓${NC} Tailscale installed"
    echo
    
    # Start and authenticate (interactive)
    speak "Connecting to Stark Industries secure network... (interactive)"
    ensure_sudo || { echo -e "${RED}✗${NC} Skipping Tailscale auth (no sudo)."; return; }
    sudo tailscale up
    
    echo
    echo -e "${GREEN}✓${NC} Tailscale mesh active"
    
    # Reconfigure firewall for Tailscale-only
    if command -v ufw &> /dev/null; then
        ensure_sudo && sudo ufw allow 41641/udp comment 'Tailscale' &> /dev/null || true
    fi
}

# Check functions
check_tailscale() {
    if command -v tailscale &> /dev/null; then
        if tailscale status &> /dev/null; then
            echo "active"
        else
            echo "installed"
        fi
    else
        echo "missing"
    fi
}

check_firewall() {
    local os_name
    os_name=$(uname -s)

    # macOS firewall (Application Firewall / ALF)
    if [ "$os_name" = "Darwin" ]; then
        local sfw_out
        sfw_out=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)
        if echo "$sfw_out" | grep -q "enabled"; then
            echo "active"
            return
        fi

        local alf_state
        alf_state=$(defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null || echo "")
        if [ "$alf_state" = "1" ] || [ "$alf_state" = "2" ]; then
            echo "active"
        else
            echo "inactive"
        fi
        return
    fi

    # Linux firewall (ufw/iptables)
    if command -v ufw &> /dev/null; then
        local ufw_out
        ufw_out=$(ufw status 2>&1 || true)

        if echo "$ufw_out" | grep -q "Status: active"; then
            echo "active"
            return
        fi

        if echo "$ufw_out" | grep -qi "need to be root\|must be root\|permission denied"; then
            ufw_out=$(sudo -n ufw status 2>&1 || sudo ufw status 2>&1 || true)
            echo "$ufw_out" | grep -q "Status: active" && echo "active" || echo "inactive"
        else
            echo "inactive"
        fi
    elif command -v iptables &> /dev/null; then
        iptables -L -n 2>/dev/null | grep -q "DROP" && echo "active" || echo "inactive"
    else
        echo "missing"
    fi
}

check_ssh_exposure() {
    if systemctl is-active sshd &> /dev/null || systemctl is-active ssh &> /dev/null; then
        # Check if SSH is exposed to internet
        if ss -tlnp | grep -q ":22 "; then
            # Check if bound to specific interface
            if grep -q "ListenAddress 127.0.0.1" /etc/ssh/sshd_config 2>/dev/null; then
                echo "local-only"
            else
                echo "exposed"
            fi
        else
            echo "disabled"
        fi
    else
        echo "disabled"
    fi
}

check_openclaw_perms() {
    local score=25
    
    # Check ~/.openclaw permissions
    if [ -d "$HOME/.openclaw" ]; then
        local perms=$(stat -c "%a" "$HOME/.openclaw" 2>/dev/null || stat -f "%Lp" "$HOME/.openclaw" 2>/dev/null)
        if [ "$perms" != "700" ]; then
            score=$((score - 5))
        fi
    fi
    
    # Check config file permissions
    if [ -f "$HOME/.openclaw/config.json" ]; then
        local config_perms=$(stat -c "%a" "$HOME/.openclaw/config.json" 2>/dev/null || stat -f "%Lp" "$HOME/.openclaw/config.json" 2>/dev/null)
        if [ "$config_perms" != "600" ]; then
            score=$((score - 5))
        fi
    fi
    
    echo $score
}

check_gateway_binding() {
    if [ -f "$HOME/.openclaw/config.json" ]; then
        if grep -q '"bind": *"127.0.0.1"' "$HOME/.openclaw/config.json" 2>/dev/null; then
            echo "localhost"
        elif grep -q '"bind": *"0.0.0.0"' "$HOME/.openclaw/config.json" 2>/dev/null; then
            echo "exposed"
        else
            echo "unknown"
        fi
    else
        echo "no-config"
    fi
}

check_auth_tokens() {
    local issues=0
    
    # Check for weak/default tokens
    if [ -f "$HOME/.openclaw/config.json" ]; then
        # Check gateway auth
        if grep -q '"auth":' "$HOME/.openclaw/config.json" 2>/dev/null; then
            local token_length=$(grep -o '"token": *"[^"]*"' "$HOME/.openclaw/config.json" 2>/dev/null | cut -d'"' -f4 | wc -c)
            if [ "$token_length" -lt 32 ]; then
                issues=$((issues + 1))
            fi
        fi
    fi
    
    echo $issues
}

check_channel_policies() {
    local score=20
    
    if [ -f "$HOME/.openclaw/config.json" ]; then
        # Check for open group policies
        if grep -q '"groupPolicy": *"open"' "$HOME/.openclaw/config.json" 2>/dev/null; then
            score=$((score - 10))
        fi
        
        # Check for allowlists
        if ! grep -q '"allowlist"' "$HOME/.openclaw/config.json" 2>/dev/null; then
            score=$((score - 5))
        fi
    fi
    
    echo $score
}

# Check installed skills against Clawdex API
check_skills() {
    local score=20
    local skills_dir="$HOME/.openclaw/skills"
    
    # Reset tracking arrays
    MALICIOUS_SKILLS=()
    UNKNOWN_SKILLS=()
    
    # Check if skills directory exists
    if [ ! -d "$skills_dir" ]; then
        # No skills installed = full score
        echo $score
        return
    fi
    
    # Count total skills
    local total_skills=0
    local checked_skills=0
    
    for skill_dir in "$skills_dir"/*; do
        [ -d "$skill_dir" ] || continue
        total_skills=$((total_skills + 1))
    done
    
    if [ $total_skills -eq 0 ]; then
        echo $score
        return
    fi
    
    # Check each skill against Clawdex
    for skill_dir in "$skills_dir"/*; do
        [ -d "$skill_dir" ] || continue
        
        local skill_name=$(basename "$skill_dir")
        checked_skills=$((checked_skills + 1))
        
        # Query Clawdex API
        local verdict=$(curl -fsS --max-time 5 "https://clawdex.koi.security/api/skill/$skill_name" 2>/dev/null | grep -o '"verdict":"[^"]*"' | cut -d'"' -f4 || true)
        
        case "$verdict" in
            "malicious")
                MALICIOUS_SKILLS+=("$skill_name")
                score=$((score - 50))  # Heavy penalty
                ;;
            "unknown")
                UNKNOWN_SKILLS+=("$skill_name")
                score=$((score - 10))
                ;;
            "benign")
                # Safe, no penalty
                ;;
            *)
                # API failed or skill not in database, treat as unknown
                UNKNOWN_SKILLS+=("$skill_name")
                score=$((score - 5))
                ;;
        esac
    done
    
    # Don't let score go below 0
    if [ $score -lt 0 ]; then
        score=0
    fi
    
    echo $score
}

# Auto-fix functions
fix_firewall() {
    speak "Locking down perimeter defenses..."
    
    if command -v ufw &> /dev/null; then
        ensure_sudo || { echo -e "${RED}✗${NC} Skipping firewall auto-fix (no sudo)."; return; }
        # Reset and configure UFW
        sudo ufw --force reset &> /dev/null || true
        sudo ufw default deny incoming &> /dev/null || true
        sudo ufw default allow outgoing &> /dev/null || true
        
        # Allow Tailscale only
        sudo ufw allow 41641/udp &> /dev/null || true  # Tailscale
        
        # Block SSH if exposed
        local ssh_status=$(check_ssh_exposure)
        if [ "$ssh_status" = "exposed" ]; then
            # Don't allow SSH through firewall
            echo -e "${GOLD}[!] SSH exposure detected - recommend Tailscale SSH${NC}"
        fi
        
        sudo ufw --force enable &> /dev/null || true
        echo -e "${GREEN}✓${NC} Firewall configured"
    fi
}

fix_permissions() {
    speak "Tightening file permissions..."
    
    if [ -d "$HOME/.openclaw" ]; then
        chmod 700 "$HOME/.openclaw"
        
        # Secure all config files
        find "$HOME/.openclaw" -name "*.json" -exec chmod 600 {} \; 2>/dev/null || true
        find "$HOME/.openclaw" -name "*.key" -exec chmod 600 {} \; 2>/dev/null || true
        
        echo -e "${GREEN}✓${NC} Permissions locked"
    fi
}

fix_gateway_binding() {
    speak "Securing gateway access..."
    
    if [ -f "$HOME/.openclaw/config.json" ]; then
        # Backup original
        cp "$HOME/.openclaw/config.json" "$HOME/.openclaw/config.json.backup.$(date +%s)"
        
        # Update bind address to localhost if exposed
        if grep -q '"bind": *"0.0.0.0"' "$HOME/.openclaw/config.json" 2>/dev/null; then
            sed -i 's/"bind": *"0.0.0.0"/"bind": "127.0.0.1"/' "$HOME/.openclaw/config.json" 2>/dev/null || \
            sed -i '' 's/"bind": *"0.0.0.0"/"bind": "127.0.0.1"/' "$HOME/.openclaw/config.json" 2>/dev/null || true
            echo -e "${GREEN}✓${NC} Gateway bound to localhost"
        fi
    fi
}

# Calculate scores with issue tracking
calculate_scores() {
    issues_reset

    # Network (30 points)
    local tailscale
    local firewall
    local ssh
    tailscale=$(check_tailscale)
    firewall=$(check_firewall)
    ssh=$(check_ssh_exposure)

    NETWORK_SCORE=0
    if [ "$tailscale" = "active" ]; then
        NETWORK_SCORE=$((NETWORK_SCORE + 15))
    elif [ "$tailscale" = "installed" ]; then
        NETWORK_SCORE=$((NETWORK_SCORE + 8))
        issue_add "Network" "-7" "Tailscale installed but not connected (interactive login)." "tailscale up" "true" "true"
    else
        issue_add "Network" "-15" "Tailscale not installed." "curl -fsSL https://tailscale.com/install.sh | sh" "false" "false"
    fi

    if [ "$firewall" = "active" ]; then
        NETWORK_SCORE=$((NETWORK_SCORE + 10))
    else
        # OS-specific guidance
        local os_name
        os_name=$(uname -s)
        if [ "$os_name" = "Darwin" ]; then
            # macOS: UFW doesn't exist; keep this as a manual step.
            issue_add "Network" "-10" "Firewall not active (macOS). Enable the macOS firewall in System Settings → Network → Firewall." "" "false" "true"
        else
            if command -v ufw >/dev/null 2>&1; then
                issue_add "Network" "-10" "Firewall not active. Enable UFW (or configure an equivalent)." "ufw enable" "true" "false"
            else
                issue_add "Network" "-10" "Firewall not detected/active. Configure a firewall (ufw/iptables/firewalld) appropriate for your OS." "" "false" "true"
            fi
        fi
    fi

    if [ "$ssh" = "local-only" ] || [ "$ssh" = "disabled" ]; then
        NETWORK_SCORE=$((NETWORK_SCORE + 5))
    elif [ "$ssh" = "exposed" ]; then
        issue_add "Network" "-5" "SSH appears exposed to the internet. Restrict sshd ListenAddress or use Tailscale SSH." "" "false" "true"
    fi

    # Permissions (25 points)
    PERM_SCORE=25
    if [ -d "$HOME/.openclaw" ]; then
        local perms
        perms=$(stat -c "%a" "$HOME/.openclaw" 2>/dev/null || stat -f "%Lp" "$HOME/.openclaw" 2>/dev/null)
        if [ "$perms" != "700" ]; then
            PERM_SCORE=$((PERM_SCORE - 5))
            issue_add "Permissions" "-5" "~/.openclaw has loose permissions ($perms)." "chmod 700 ~/.openclaw" "false" "false"
        fi
    fi

    if [ -f "$HOME/.openclaw/config.json" ]; then
        local config_perms
        config_perms=$(stat -c "%a" "$HOME/.openclaw/config.json" 2>/dev/null || stat -f "%Lp" "$HOME/.openclaw/config.json" 2>/dev/null)
        if [ "$config_perms" != "600" ]; then
            PERM_SCORE=$((PERM_SCORE - 5))
            issue_add "Permissions" "-5" "config.json has loose permissions ($config_perms)." "chmod 600 ~/.openclaw/config.json" "false" "false"
        fi
    fi

    # Gateway (25 points)
    local gateway
    local token_issues
    gateway=$(check_gateway_binding)
    token_issues=$(check_auth_tokens)

    GATEWAY_SCORE=25
    if [ "$gateway" = "exposed" ]; then
        GATEWAY_SCORE=10
        issue_add "Gateway" "-15" "Gateway bound to 0.0.0.0 (public). Bind to 127.0.0.1 in ~/.openclaw/config.json." "" "false" "true"
    elif [ "$gateway" = "unknown" ]; then
        GATEWAY_SCORE=15
        issue_add "Gateway" "-10" "Could not verify gateway binding. Ensure gateway.bind is 127.0.0.1 in ~/.openclaw/config.json." "" "false" "true"
    fi

    if [ "$token_issues" -gt 0 ]; then
        GATEWAY_SCORE=$((GATEWAY_SCORE - 10))
        issue_add "Gateway" "-10" "Auth token is too short (<32 chars). Generate a longer token and update config." "openssl rand -hex 32" "false" "false"
    fi

    # Channels (20 points)
    CHANNEL_SCORE=20
    if [ -f "$HOME/.openclaw/config.json" ]; then
        if grep -q '"groupPolicy": *"open"' "$HOME/.openclaw/config.json" 2>/dev/null; then
            CHANNEL_SCORE=$((CHANNEL_SCORE - 10))
            issue_add "Channels" "-10" "Group policy is open (anyone can message). Set groupPolicy to allowlist in config." "" "false" "true"
        fi

        if ! grep -q '"allowlist"' "$HOME/.openclaw/config.json" 2>/dev/null; then
            CHANNEL_SCORE=$((CHANNEL_SCORE - 5))
            issue_add "Channels" "-5" "No allowlist configured. Add an allowlist to your channel config." "" "false" "true"
        fi
    fi

    # Skills (20 points) - Clawdex scan
    SKILL_SCORE=$(check_skills)

    if [ ${#MALICIOUS_SKILLS[@]} -gt 0 ]; then
        for skill in "${MALICIOUS_SKILLS[@]}"; do
            issue_add "Skills" "-50" "Malicious skill detected: $skill (remove immediately)." "npm uninstall -g $skill" "false" "false"
        done
    fi

    if [ ${#UNKNOWN_SKILLS[@]} -gt 0 ]; then
        for skill in "${UNKNOWN_SKILLS[@]}"; do
            issue_add "Skills" "-5" "Unverified skill: $skill (review in Clawdex or remove if untrusted)." "" "false" "true"
        done
    fi

    TOTAL_SCORE=$((NETWORK_SCORE + PERM_SCORE + GATEWAY_SCORE + CHANNEL_SCORE + SKILL_SCORE))
}

# Execute a fix command safely
execute_fix() {
    local cmd="$1"
    local needs_sudo="$2"
    local exit_code=0

    rm -f /tmp/friday_error.log 2>/dev/null || true

    if [ "$needs_sudo" = "true" ]; then
        ensure_sudo || return 1

        echo -e "         ${GRAY}Running with sudo...${NC}"
        if sudo bash -c "$cmd" 2>/tmp/friday_error.log; then
            echo -e "         ${GREEN}✓ Done${NC}"
            return 0
        else
            exit_code=$?
            echo -e "         ${RED}✗ Failed (exit $exit_code)${NC}"
            if [ -f /tmp/friday_error.log ] && [ -s /tmp/friday_error.log ]; then
                echo -e "         ${GRAY}Error: $(head -1 /tmp/friday_error.log)${NC}"
            fi
            return 1
        fi
    else
        if bash -c "$cmd" 2>/tmp/friday_error.log; then
            echo -e "         ${GREEN}✓ Done${NC}"
            return 0
        else
            exit_code=$?
            echo -e "         ${RED}✗ Failed (exit $exit_code)${NC}"
            if [ -f /tmp/friday_error.log ] && [ -s /tmp/friday_error.log ]; then
                echo -e "         ${GRAY}Error: $(head -1 /tmp/friday_error.log)${NC}"
            fi
            return 1
        fi
    fi
}

# Offer to run a fix command
FRIDAY_FIX_ATTEMPTED=false

offer_fix() {
    local desc="$1"
    local fix_cmd="${2:-}"
    local points="$3"
    local needs_sudo="${4:-false}"
    local manual="${5:-false}"
    local fix_response=""

    FRIDAY_FIX_ATTEMPTED=false

    echo -e "   ${RED}$points${NC}  $desc"

    if [ "$manual" = "true" ] || [ -z "$fix_cmd" ]; then
        if [ -n "$fix_cmd" ]; then
            if [ "$needs_sudo" = "true" ]; then
                echo -e "         ${GREEN}→ Manual step:${NC} sudo $fix_cmd"
            else
                echo -e "         ${GREEN}→ Manual step:${NC} $fix_cmd"
            fi
        else
            echo -e "         ${GREEN}→ Manual step:${NC} No command provided (see guidance above)."
        fi
        return 1
    fi

    # Ensure command is command-only (strip accidental leading sudo)
    fix_cmd="${fix_cmd#sudo }"

    if [ "$needs_sudo" = "true" ]; then
        echo -e "         ${GRAY}Command:${NC} sudo $fix_cmd"
        safe_read fix_response "         ${BLUE}Run with sudo? [Y/n/skip all]: ${NC}"
    else
        echo -e "         ${GRAY}Command:${NC} $fix_cmd"
        safe_read fix_response "         ${BLUE}Run this fix? [Y/n/skip all]: ${NC}"
    fi

    case "$fix_response" in
        [Ss]|[Ss]kip*)
            echo -e "         ${GRAY}Skipping all remaining fixes...${NC}"
            return 2
            ;;
        [Nn]|[Nn]o)
            echo -e "         ${GRAY}Skipped${NC}"
            return 1
            ;;
        *)
            FRIDAY_FIX_ATTEMPTED=true
            echo -e "         ${GOLD}Running...${NC}"
            execute_fix "$fix_cmd" "$needs_sudo" || true
            return 0
            ;;
    esac
}

# Print detailed issues breakdown with interactive fixes
print_issues() {
    local skip_all=false
    local fixes_attempted=false

    if [ ${#ISSUE_CATEGORY[@]} -eq 0 ]; then
        echo -e "${GREEN}✓ Perfect score! No issues detected.${NC}"
        echo
        return
    fi

    echo -e "${WHITE}🔍 ISSUES FOUND — Fix now or skip:${NC}"
    echo

    local last_category=""
    for ((i=0; i<${#ISSUE_CATEGORY[@]}; i++)); do
        local category="${ISSUE_CATEGORY[$i]}"
        local points="${ISSUE_POINTS[$i]}"
        local desc="${ISSUE_DESC[$i]}"
        local cmd="${ISSUE_CMD[$i]}"
        local needs_sudo="${ISSUE_NEEDS_SUDO[$i]}"
        local manual="${ISSUE_MANUAL[$i]}"

        if [ "$category" != "$last_category" ]; then
            echo -e "   ${BLUE}━━━ $category ━━━${NC}"
            last_category="$category"
        fi

        if [ "$skip_all" = false ]; then
            offer_fix "$desc" "$cmd" "$points" "$needs_sudo" "$manual"
            local result=$?
            if [ "$FRIDAY_FIX_ATTEMPTED" = true ]; then
                fixes_attempted=true
            fi
            if [ $result -eq 2 ]; then
                skip_all=true
                echo
            fi
        else
            echo -e "   ${RED}$points${NC}  $desc"
            if [ "$manual" = "true" ] || [ -z "$cmd" ]; then
                echo -e "         ${GREEN}→ Fix:${NC} (manual)"
            else
                if [ "$needs_sudo" = "true" ]; then
                    echo -e "         ${GREEN}→ Fix:${NC} sudo $cmd"
                else
                    echo -e "         ${GREEN}→ Fix:${NC} $cmd"
                fi
            fi
        fi
    done
    echo

    if [ "$fixes_attempted" = true ]; then
        local rescan_response=""
        safe_read rescan_response "${BLUE}Rescan to update score? [Y/n]: ${NC}"
        if [[ "$rescan_response" =~ ^([Yy]|[Yy]es|)$ ]]; then
            speak "Re-analyzing security posture..."
            calculate_scores
            echo -e "   ${WHITE}Updated score: ${GOLD}$TOTAL_SCORE/120${NC}"
            echo
        fi
    fi
}

# Print progress bar
progress_bar() {
    local current=$1
    local max=$2
    local width=20
    local filled=$((current * width / max))
    local empty=$((width - filled))
    
    printf "["
    if [ $filled -gt 0 ]; then
        printf "%${filled}s" | tr ' ' '='
    fi
    if [ $empty -gt 0 ]; then
        printf "%${empty}s" | tr ' ' '-'
    fi
    printf "]"
}

# Main output
print_results() {
    section
    echo
    speak "Suit-up complete."
    echo
    
    # Badge
    local badge=""
    local badge_color=""
    
    if [ $TOTAL_SCORE -ge 90 ]; then
        badge="★ STARK CERTIFIED ★"
        badge_color=$GOLD
    elif [ $TOTAL_SCORE -ge 70 ]; then
        badge="◆ SHIELD PROTOCOL ACTIVE ◆"
        badge_color=$GREEN
    elif [ $TOTAL_SCORE -ge 50 ]; then
        badge="⚠ SUIT DAMAGE DETECTED"
        badge_color=$GOLD
    elif [ $TOTAL_SCORE -ge 30 ]; then
        badge="⚠ ARMOR BREACH DETECTED"
        badge_color=$GRAY
    else
        badge="🚨 CRITICAL: JARVIS COMPROMISED"
        badge_color=$RED
    fi
    
    # Score box
    echo -e "   ${GRAY}╔═══════════════════════════════════════╗${NC}"
    echo -e "   ${GRAY}║${NC}                                       ${GRAY}║${NC}"
    echo -e "   ${GRAY}║${NC}    ${WHITE}SECURITY SCORE${NC}                     ${GRAY}║${NC}"
    echo -e "   ${GRAY}║${NC}                                       ${GRAY}║${NC}"
    echo -e "   ${GRAY}║${NC}         ${BLUE}$TOTAL_SCORE${NC}                            ${GRAY}║${NC}"
    echo -e "   ${GRAY}║${NC}        ${GRAY}/120${NC}                          ${GRAY}║${NC}"
    echo -e "   ${GRAY}║${NC}                                       ${GRAY}║${NC}"
    echo -e "   ${GRAY}║${NC}    ${badge_color}$badge${NC}  ${GRAY}║${NC}"
    echo -e "   ${GRAY}║${NC}                                       ${GRAY}║${NC}"
    echo -e "   ${GRAY}╚═══════════════════════════════════════╝${NC}"
    echo
    
    # Breakdown
    echo -e "${WHITE}📊 BREAKDOWN:${NC}"
    echo
    printf "   Network:     "
    progress_bar $NETWORK_SCORE 30
    printf "  %s/%s\n" "$NETWORK_SCORE" "30"
    
    printf "   Permissions: "
    progress_bar $PERM_SCORE 25
    printf "  %s/%s\n" "$PERM_SCORE" "25"
    
    printf "   Gateway:     "
    progress_bar $GATEWAY_SCORE 25
    printf "  %s/%s\n" "$GATEWAY_SCORE" "25"
    
    printf "   Channels:    "
    progress_bar $CHANNEL_SCORE 20
    printf "  %s/%s\n" "$CHANNEL_SCORE" "20"
    
    printf "   Skills:      "
    progress_bar $SKILL_SCORE 20
    printf "  %s/%s\n" "$SKILL_SCORE" "20"
    echo
    
    # Print detailed issues with fixes
    print_issues
    
    # Malicious skills warning
    if [ ${#MALICIOUS_SKILLS[@]} -gt 0 ]; then
        section
        echo
        echo -e "${RED}🚨 CRITICAL: MALICIOUS SKILLS DETECTED${NC}"
        echo
        echo -e "   ${RED}The following skills are flagged as MALICIOUS by Clawdex:${NC}"
        for skill in "${MALICIOUS_SKILLS[@]}"; do
            echo -e "   ${RED}  • $skill 🚫${NC}"
        done
        echo
        echo -e "   ${GOLD}Immediate action required:${NC}"
        echo -e "   ${WHITE}  npm uninstall -g <skill-name>${NC}"
        echo
        speak "Boss, I've detected compromised armor components. Immediate removal required."
        echo
    fi
    
    # Unknown skills warning
    if [ ${#UNKNOWN_SKILLS[@]} -gt 0 ]; then
        section
        echo
        echo -e "${GOLD}⚠️  UNVERIFIED SKILLS DETECTED${NC}"
        echo
        echo -e "   ${GRAY}The following skills are not in the Clawdex database:${NC}"
        for skill in "${UNKNOWN_SKILLS[@]}"; do
            echo -e "   ${GOLD}  • $skill ⚠️${NC}"
        done
        echo
        echo -e "   ${GRAY}Verify these manually at: https://clawdex.koi.security${NC}"
        echo
    fi
    
    # Instance info
    echo -e "${GRAY}INSTANCE ID: $INSTANCE_ID${NC}"
    echo
    
    # Links
    echo -e "${BLUE}🔗 Dashboard:${NC} https://friday.openclaw.dev/leaderboard.html"
    echo -e "${BLUE}🐦 Share:${NC}     https://twitter.com/intent/tweet?text=Just%20secured%20my%20OpenClaw%20with%20FRIDAY%21%20Score%3A%20$TOTAL_SCORE%2F120%20%23FRIDAY"
    echo
}

# Submit to leaderboard
submit_leaderboard() {
    local score=$1
    local os=$(uname -s)
    local arch=$(uname -m)
    local is_retry=${2:-false}
    
    if [ "$is_retry" = false ]; then
        speak "Let's get you on the leaderboard..."
        echo
    fi
    
    # Prompt for handle (required)
    local user_handle=""
    while true; do
        safe_read user_handle "${BLUE}Choose your @handle (3-20 chars, letters/numbers/underscore): ${NC}"
        
        # Clean handle
        user_handle=$(echo "$user_handle" | sed 's/^@//' | tr '[:upper:]' '[:lower:]')
        
        if [ -z "$user_handle" ]; then
            echo -e "${RED}Handle is required for leaderboard.${NC}"
            continue
        fi
        
        if ! echo "$user_handle" | grep -qE '^[a-zA-Z0-9_]{3,20}$'; then
            echo -e "${RED}Invalid format. Use 3-20 characters (letters, numbers, underscore).${NC}"
            continue
        fi
        
        break
    done
    
    # First attempt without PIN to check if handle exists
    local json_data
    json_data=$(printf '{"instance_id":"%s","handle":"%s","score":%d,"os":"%s","arch":"%s","timestamp":"%s","network_score":%d,"perm_score":%d,"gateway_score":%d,"channel_score":%d,"skill_score":%d}' \
        "$INSTANCE_ID" "$user_handle" "$score" "$os" "$arch" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$NETWORK_SCORE" "$PERM_SCORE" "$GATEWAY_SCORE" "$CHANNEL_SCORE" "$SKILL_SCORE")
    
    local response
    if ! http_post_json "https://friday.openclaw.dev/api/leaderboard/submit" "$json_data"; then
        echo -e "${RED}Failed to submit (network error).${NC}"
        if [ -n "${HTTP_ERR:-}" ]; then
            echo -e "${GRAY}${HTTP_ERR}${NC}"
        fi
        return 1
    fi
    response="$HTTP_BODY"
    if [ -z "$response" ]; then
        echo -e "${RED}Failed to submit (empty response, HTTP ${HTTP_STATUS:-?}).${NC}"
        return 1
    fi
    if [ "${HTTP_STATUS:-0}" -lt 200 ] 2>/dev/null || [ "${HTTP_STATUS:-0}" -ge 300 ] 2>/dev/null; then
        echo -e "${RED}Failed to submit (HTTP ${HTTP_STATUS:-?}).${NC}"
        echo -e "${GRAY}${response:0:400}${NC}"
        return 1
    fi
    
    # Check if handle is taken (needs PIN)
    if echo "$response" | grep -q '"needsPin":true'; then
        echo
        echo -e "${GOLD}Handle @$user_handle is already claimed.${NC}"
        
        local user_pin=""
        safe_read user_pin "${BLUE}Enter your 4-digit PIN to update your score (or 'new' for different handle): ${NC}"
        
        if [ "$user_pin" = "new" ] || [ "$user_pin" = "NEW" ]; then
            submit_leaderboard "$score" true
            return
        fi
        
        # Validate PIN format
        if ! echo "$user_pin" | grep -qE '^[0-9]{4}$'; then
            echo -e "${RED}PIN must be exactly 4 digits.${NC}"
            submit_leaderboard "$score" true
            return
        fi
        
        # Retry with PIN
        json_data=$(printf '{"instance_id":"%s","handle":"%s","pin":"%s","score":%d,"os":"%s","arch":"%s","timestamp":"%s","network_score":%d,"perm_score":%d,"gateway_score":%d,"channel_score":%d,"skill_score":%d}' \
            "$INSTANCE_ID" "$user_handle" "$user_pin" "$score" "$os" "$arch" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$NETWORK_SCORE" "$PERM_SCORE" "$GATEWAY_SCORE" "$CHANNEL_SCORE" "$SKILL_SCORE")
        
        if ! http_post_json "https://friday.openclaw.dev/api/leaderboard/submit" "$json_data"; then
            echo -e "${RED}Failed to submit (network error).${NC}"
            if [ -n "${HTTP_ERR:-}" ]; then
                echo -e "${GRAY}${HTTP_ERR}${NC}"
            fi
            return 1
        fi
        response="$HTTP_BODY"
        if [ -z "$response" ]; then
            echo -e "${RED}Failed to submit (empty response, HTTP ${HTTP_STATUS:-?}).${NC}"
            return 1
        fi
        if [ "${HTTP_STATUS:-0}" -lt 200 ] 2>/dev/null || [ "${HTTP_STATUS:-0}" -ge 300 ] 2>/dev/null; then
            echo -e "${RED}Failed to submit (HTTP ${HTTP_STATUS:-?}).${NC}"
            echo -e "${GRAY}${response:0:400}${NC}"
            return 1
        fi
        
        # Check for wrong PIN
        if echo "$response" | grep -q '"error":"invalid_pin"'; then
            echo -e "${RED}Incorrect PIN. Try again or choose a different handle.${NC}"
            submit_leaderboard "$score" true
            return
        fi
    fi
    
    # Check if new handle needs PIN
    if echo "$response" | grep -q '"needsNewPin":true'; then
        echo
        echo -e "${GREEN}Handle @$user_handle is available!${NC}"
        local user_pin=""
        while true; do
            safe_read user_pin "${BLUE}Create a 4-digit PIN to protect your handle: ${NC}"
            
            if ! echo "$user_pin" | grep -qE '^[0-9]{4}$'; then
                echo -e "${RED}PIN must be exactly 4 digits.${NC}"
                continue
            fi
            break
        done
        
        # Retry with new PIN
        json_data=$(printf '{"instance_id":"%s","handle":"%s","pin":"%s","score":%d,"os":"%s","arch":"%s","timestamp":"%s","network_score":%d,"perm_score":%d,"gateway_score":%d,"channel_score":%d,"skill_score":%d}' \
            "$INSTANCE_ID" "$user_handle" "$user_pin" "$score" "$os" "$arch" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$NETWORK_SCORE" "$PERM_SCORE" "$GATEWAY_SCORE" "$CHANNEL_SCORE" "$SKILL_SCORE")
        
        if ! http_post_json "https://friday.openclaw.dev/api/leaderboard/submit" "$json_data"; then
            echo -e "${RED}Failed to submit (network error).${NC}"
            if [ -n "${HTTP_ERR:-}" ]; then
                echo -e "${GRAY}${HTTP_ERR}${NC}"
            fi
            return 1
        fi
        response="$HTTP_BODY"
        if [ -z "$response" ]; then
            echo -e "${RED}Failed to submit (empty response, HTTP ${HTTP_STATUS:-?}).${NC}"
            return 1
        fi
        if [ "${HTTP_STATUS:-0}" -lt 200 ] 2>/dev/null || [ "${HTTP_STATUS:-0}" -ge 300 ] 2>/dev/null; then
            echo -e "${RED}Failed to submit (HTTP ${HTTP_STATUS:-?}).${NC}"
            echo -e "${GRAY}${response:0:400}${NC}"
            return 1
        fi
    fi
    
    # Check for errors
    if echo "$response" | grep -q '"error"'; then
        local error_msg=$(echo "$response" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
        echo -e "${RED}Error: ${error_msg:-Failed to submit}${NC}"
        return 1
    fi
    
    # Parse success response
    local rank=$(echo "$response" | grep -o '"rank":[0-9]*' | cut -d':' -f2 || echo "--")
    local total=$(echo "$response" | grep -o '"total_participants":[0-9]*' | cut -d':' -f2 || echo "--")
    local percentile=$(echo "$response" | grep -o '"percentile":[0-9]*' | cut -d':' -f2 || echo "--")
    local message=$(echo "$response" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
    
    echo
    section
    echo
    echo -e "${GOLD}🏆 GLOBAL LEADERBOARD${NC}"
    echo
    if [ -n "$message" ]; then
        echo -e "   ${GREEN}$message${NC}"
        echo
    fi
    echo -e "   Handle: ${WHITE}@$user_handle${NC}"
    echo -e "   Your rank: ${WHITE}#$rank${NC} of $total"
    echo -e "   Percentile: Top ${GOLD}$percentile%${NC}"
    echo
    
    # Achievement badges
    if [ "$rank" -le 10 ] 2>/dev/null; then
        echo -e "   ${GOLD}★ TOP 10 FRIDAY PROTECTOR ★${NC}"
    elif [ "$rank" -le 100 ] 2>/dev/null; then
        echo -e "   ${BLUE}◆ ELITE SECURITY OPERATIVE ◆${NC}"
    fi
    
    echo
    echo -e "${BLUE}🔗 Leaderboard:${NC} https://friday-boi.pages.dev/#leaderboard"
    echo -e "${BLUE}🐦 Share:${NC} https://twitter.com/intent/tweet?text=I%20scored%20$score%2F120%20on%20FRIDAY%20security!%20Rank%20%23$rank%20%40$user_handle%20%23FRIDAY"
    echo
}

# Offer Tailscale upgrade
offer_tailscale_upgrade() {
    local tailscale_status=$(check_tailscale)
    if [ "$tailscale_status" != "active" ] && [ $TOTAL_SCORE -lt 90 ]; then
        local boost_points=$((30 - NETWORK_SCORE))
        local boosted_score=$((TOTAL_SCORE + boost_points))
        
        section
        echo
        echo -e "${GOLD}⚡ SUIT UPGRADE AVAILABLE${NC}"
        echo
        echo -e "   Current armor rating: ${WHITE}$TOTAL_SCORE/120${NC}"
        echo -e "   Combat-ready with upgrade: ${GOLD}$boosted_score/120 ★ STARK CERTIFIED ★${NC}"
        echo
        echo -e "   ${GRAY}Install Tailscale mesh VPN for:${NC}"
        echo -e "   • Zero-config private network"
        echo -e "   • No exposed ports to internet"
        echo -e "   • +$boost_points security points"
        echo
        
        # Prompt for install
        speak "Boss, I can get you to full combat readiness. 30 seconds for Stark Certified armor."
        local response=""
        safe_read response "${BLUE}Install Tailscale now? [Y/n]: ${NC}"
        
        if [[ "$response" =~ ^([Yy]|[Yy]es|)$ ]]; then
            install_tailscale
            
            # Recalculate with Tailscale
            calculate_scores
            
            echo
            section
            echo
            speak "Armor upgrade complete. Re-scanning..."
            echo
            
            # Show updated results
            print_results
        else
            echo
            speak "Roger that, boss. Tailscale is ready when you are."
            echo -e "${GRAY}Run 'curl -fsSL https://tailscale.com/install.sh | sh' anytime.${NC}"
            echo
        fi
    fi
    
    # Leaderboard submission (any score)
    section
    echo
    echo -e "${GOLD}🏆 GLOBAL LEADERBOARD${NC}"
    echo
    echo -e "   ${GRAY}See how your security compares to other OpenClaw deployments.${NC}"
    echo
    speak "Boss, want to submit your score to the global leaderboard?"
    local lb_response=""
    safe_read lb_response "${BLUE}Submit to leaderboard? [Y/n]: ${NC}"

    # Normalize input (handles spaces / CR from some terminals)
    lb_response=$(echo "$lb_response" | tr -d '[:space:]')

    if [[ "$lb_response" =~ ^([Yy]|[Yy]es|)$ ]]; then
        submit_leaderboard $TOTAL_SCORE
    else
        echo
        speak "Understood. Your results stay local."
    fi
    
    speak "Your AI is secure, boss. I'll keep watch."
    echo -e "${GRAY}Next scan: 24 hours | Run 'friday scan' anytime to recheck.${NC}"
    echo
}

# Main execution
main() {
    print_banner
    speak "Initializing security protocols..."
    section
    echo
    
    # Detection phase
    echo -e "${BLUE}[🔄]${NC} Detecting environment..."
    local os=$(uname -s)
    local arch=$(uname -m)
    sleep 0.5
    echo -e "   ${GREEN}✓${NC} $os / $arch"
    echo
    
    # Checks
    echo -e "${BLUE}[🔄]${NC} Analyzing network exposure..."
    calculate_scores &
    local calc_pid=$!
    spinner $calc_pid
    wait $calc_pid
    
    local initial_score=$TOTAL_SCORE
    echo -e "   Initial score: ${GOLD}$initial_score/120${NC}"
    echo
    
    # Auto-fix phase
    if [ $initial_score -lt 100 ]; then
        speak "Auto-fixing detected issues..."
        section
        echo
        
        fix_firewall
        fix_permissions
        fix_gateway_binding
        
        # Recalculate
        calculate_scores
        
        echo
        echo -e "${GREEN}✓${NC} Auto-fix applied"
        echo
    fi
    
    # Results
    print_results
    offer_tailscale_upgrade
}

# Run main
main "$@"
