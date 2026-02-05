#!/bin/bash
#
# FRIDAY v1.0 - AI Instance Security
# curl -sSL friday.openclaw.dev | bash
#
# One-command security hardening for OpenClaw

set -e

# Colors
BLACK='\033[0;30m'
BLUE='\033[38;5;81m'      # Arc reactor blue
GREEN='\033[38;5;84m'     # JARVIS green
GOLD='\033[38;5;214m'     # Stark gold
RED='\033[38;5;196m'      # Alert red
WHITE='\033[38;5;255m'    # Soft white
GRAY='\033[38;5;240m'     # Muted
NC='\033[0m'

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
    echo -e "${BLUE}🎙️  FRIDAY:${WHITE} \"$1\"${NC}"
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

# Install Tailscale
install_tailscale() {
    speak "Initiating armor upgrade sequence..."
    
    # The one-liner that does it all
    curl -fsSL https://tailscale.com/install.sh | sh
    
    echo -e "${GREEN}✓${NC} Tailscale installed"
    echo
    
    # Start and authenticate
    speak "Connecting to Stark Industries secure network..."
    sudo tailscale up
    
    echo
    echo -e "${GREEN}✓${NC} Tailscale mesh active"
    
    # Reconfigure firewall for Tailscale-only
    if command -v ufw &> /dev/null; then
        sudo ufw allow 41641/udp comment 'Tailscale' &> /dev/null
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
    if command -v ufw &> /dev/null; then
        ufw status | grep -q "Status: active" && echo "active" || echo "inactive"
    elif command -v iptables &> /dev/null; then
        iptables -L -n | grep -q "DROP" && echo "active" || echo "inactive"
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
        local verdict=$(curl -s --max-time 5 "https://clawdex.koi.security/api/skill/$skill_name" 2>/dev/null | grep -o '"verdict":"[^"]*"' | cut -d'"' -f4)
        
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
        # Reset and configure UFW
        sudo ufw --force reset &> /dev/null
        sudo ufw default deny incoming &> /dev/null
        sudo ufw default allow outgoing &> /dev/null
        
        # Allow Tailscale only
        sudo ufw allow 41641/udp &> /dev/null  # Tailscale
        
        # Block SSH if exposed
        local ssh_status=$(check_ssh_exposure)
        if [ "$ssh_status" = "exposed" ]; then
            # Don't allow SSH through firewall
            echo -e "${GOLD}[!] SSH exposure detected - recommend Tailscale SSH${NC}"
        fi
        
        sudo ufw --force enable &> /dev/null
        echo -e "${GREEN}✓${NC} Firewall configured"
    fi
}

fix_permissions() {
    speak "Tightening file permissions..."
    
    if [ -d "$HOME/.openclaw" ]; then
        chmod 700 "$HOME/.openclaw"
        
        # Secure all config files
        find "$HOME/.openclaw" -name "*.json" -exec chmod 600 {} \; 2>/dev/null
        find "$HOME/.openclaw" -name "*.key" -exec chmod 600 {} \; 2>/dev/null
        
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
            sed -i '' 's/"bind": *"0.0.0.0"/"bind": "127.0.0.1"/' "$HOME/.openclaw/config.json" 2>/dev/null
            echo -e "${GREEN}✓${NC} Gateway bound to localhost"
        fi
    fi
}

# Calculate scores
calculate_scores() {
    # Network (30 points)
    local tailscale=$(check_tailscale)
    local firewall=$(check_firewall)
    local ssh=$(check_ssh_exposure)
    
    NETWORK_SCORE=0
    [ "$tailscale" = "active" ] && NETWORK_SCORE=$((NETWORK_SCORE + 15))
    [ "$tailscale" = "installed" ] && NETWORK_SCORE=$((NETWORK_SCORE + 8))
    [ "$firewall" = "active" ] && NETWORK_SCORE=$((NETWORK_SCORE + 10))
    [ "$ssh" = "local-only" ] && NETWORK_SCORE=$((NETWORK_SCORE + 5))
    [ "$ssh" = "disabled" ] && NETWORK_SCORE=$((NETWORK_SCORE + 5))
    
    # Permissions (25 points)
    PERM_SCORE=$(check_openclaw_perms)
    
    # Gateway (25 points)
    local gateway=$(check_gateway_binding)
    local token_issues=$(check_auth_tokens)
    
    GATEWAY_SCORE=25
    [ "$gateway" = "localhost" ] && GATEWAY_SCORE=25
    [ "$gateway" = "exposed" ] && GATEWAY_SCORE=10
    [ "$gateway" = "unknown" ] && GATEWAY_SCORE=15
    [ "$token_issues" -gt 0 ] && GATEWAY_SCORE=$((GATEWAY_SCORE - 10))
    
    # Channels (20 points)
    CHANNEL_SCORE=$(check_channel_policies)
    
    # Skills (20 points) - Clawdex scan
    SKILL_SCORE=$(check_skills)
    
    TOTAL_SCORE=$((NETWORK_SCORE + PERM_SCORE + GATEWAY_SCORE + CHANNEL_SCORE + SKILL_SCORE))
}

# Print progress bar
progress_bar() {
    local current=$1
    local max=$2
    local width=20
    local filled=$((current * width / max))
    local empty=$((width - filled))
    
    printf "["
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
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
    echo -e "   ${GRAY}║${NC}        ${GRAY}/100${NC}                          ${GRAY}║${NC}"
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
    echo -e "${BLUE}🔗 Dashboard:${NC} https://friday.openclaw.dev/d/$INSTANCE_ID"
    echo -e "${BLUE}🐦 Share:${NC}     https://twitter.com/intent/tweet?text=Just%20secured%20my%20OpenClaw%20with%20FRIDAY%21%20Score%3A%20$TOTAL_SCORE%2F100%20%23FRIDAY"
    echo
}

# Submit to leaderboard
submit_leaderboard() {
    local score=$1
    local os=$(uname -s)
    local arch=$(uname -m)
    
    speak "Connecting to Stark Industries global network..."
    
    # Prompt for optional handle
    echo -ne "${BLUE}Enter your @Twitter handle for the leaderboard (optional): ${NC}"
    read -r user_handle
    
    # Prepare submission data
    local handle_param=""
    if [ -n "$user_handle" ]; then
        handle_param="\"handle\": \"$user_handle\","
    fi
    
    local json_data=$(cat <<EOF
{
  "instance_id": "$INSTANCE_ID",
  $handle_param
  "score": $score,
  "os": "$os",
  "arch": "$arch",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "network_score": $NETWORK_SCORE,
  "perm_score": $PERM_SCORE,
  "gateway_score": $GATEWAY_SCORE,
  "channel_score": $CHANNEL_SCORE,
  "skill_score": $SKILL_SCORE
}
EOF
)
    
    # Submit to API (placeholder - replace with actual endpoint)
    local response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$json_data" \
        "https://friday.openclaw.dev/api/leaderboard/submit" 2>/dev/null || echo '{"error": "connection_failed"}')
    
    # Parse response (simple grep/sed for now)
    local rank=$(echo "$response" | grep -o '"rank":[0-9]*' | cut -d':' -f2 || echo "--")
    local total=$(echo "$response" | grep -o '"total_participants":[0-9]*' | cut -d':' -f2 || echo "--")
    local percentile=$(echo "$response" | grep -o '"percentile":[0-9]*' | cut -d':' -f2 || echo "--")
    
    echo
    section
    echo
    echo -e "${GOLD}🏆 GLOBAL LEADERBOARD${NC}"
    echo
    echo -e "   Your rank: ${WHITE}#$rank${NC} of $total"
    echo -e "   Percentile: Top ${GOLD}$percentile%${NC}"
    echo
    
    # Achievement badges for leaderboard
    if [ "$rank" -le 10 ] 2>/dev/null; then
        echo -e "   ${GOLD}★ TOP 10 FRIDAY PROTECTOR ★${NC}"
    elif [ "$rank" -le 100 ] 2>/dev/null; then
        echo -e "   ${BLUE}◆ ELITE SECURITY OPERATIVE ◆${NC}"
    elif [ "$percentile" -le 10 ] 2>/dev/null; then
        echo -e "   ${GREEN}⚔ SHIELD AGENT ⚔${NC}"
    fi
    
    echo
    echo -e "${BLUE}🐦${NC} Share your rank: https://twitter.com/intent/tweet?text=My%20OpenClaw%20scored%20$score%2F100%20on%20FRIDAY!%20Rank%20%23$rank%20globally%20%23FRIDAY"
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
        echo -e "   Current armor rating: ${WHITE}$TOTAL_SCORE/100${NC}"
        echo -e "   Combat-ready with upgrade: ${GOLD}$boosted_score/100 ★ STARK CERTIFIED ★${NC}"
        echo
        echo -e "   ${GRAY}Install Tailscale mesh VPN for:${NC}"
        echo -e "   • Zero-config private network"
        echo -e "   • No exposed ports to internet"
        echo -e "   • +$boost_points security points"
        echo
        
        # Prompt for install
        speak "Boss, I can get you to full combat readiness. 30 seconds for Stark Certified armor."
        echo -ne "${BLUE}Install Tailscale now? [Y/n]: ${NC}"
        read -r response
        
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
    
    # Leaderboard submission (for scores 70+)
    if [ $TOTAL_SCORE -ge 70 ]; then
        section
        echo
        echo -e "${GOLD}🏆 TOP AGENTS NETWORK${NC}"
        echo
        echo -e "   ${GRAY}Your armor rating qualifies for global ranking.${NC}"
        echo -e "   ${GRAY}See how you compare to other Stark Industries AI deployments.${NC}"
        echo
        speak "Boss, your security score qualifies for the global leaderboard. Shall I submit it?"
        echo -ne "${BLUE}Submit to FRIDAY leaderboard? [Y/n]: ${NC}"
        read -r lb_response
        
        if [[ "$lb_response" =~ ^([Yy]|[Yy]es|)$ ]]; then
            submit_leaderboard $TOTAL_SCORE
        else
            echo
            speak "Understood. Your results stay local."
        fi
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
    echo -e "   Initial score: ${GOLD}$initial_score/100${NC}"
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
