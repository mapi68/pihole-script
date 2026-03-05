#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
LIGHTBLUE='\033[1;36m'
CYAN='\033[0;36m'
BOLD='\033[1m'
ITALIC='\033[3m'
NC='\033[0m'

REFRESH=10
API="http://localhost/api"
API_KEY_FILE="/etc/pihole/cli_pw"
W=56  # total inner width of the box

# ─────────────────────────────────────────────
# AUTH
# ─────────────────────────────────────────────
get_sid() {
	[[ ! -f "$API_KEY_FILE" ]] && return
	local pw sid
	pw=$(cat "$API_KEY_FILE")
	sid=$(curl -s -X POST "$API/auth" \
		-H "Content-Type: application/json" \
		-d "{\"password\":\"$pw\"}" \
		| grep -o '"sid":"[^"]*"' | cut -d'"' -f4)
	echo "$sid"
}

# ─────────────────────────────────────────────
# API
# ─────────────────────────────────────────────
api_get() {
	local endpoint="$1" sid="$2"
	if [[ -n "$sid" ]]; then
		curl -s -H "X-FTL-SID: $sid" "$API/$endpoint"
	else
		curl -s "$API/$endpoint"
	fi
}

# ─────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────
json_val() { echo "$1" | grep -o "\"$2\":[^,}]*" | head -1 | sed 's/.*://;s/[" }]//g'; }

service_status() {
	if systemctl is-active --quiet "$1" 2>/dev/null; then
		printf "${GREEN}${BOLD}active${NC}"
	else
		printf "${RED}${BOLD}inactive${NC}"
	fi
}

# Draw a simple ASCII bar [====----] width=24
bar() {
	local val=$1 max=$2 width=24
	[[ $max -eq 0 ]] && max=1
	local filled=$(( val * width / max ))
	[[ $filled -gt $width ]] && filled=$width
	local empty=$(( width - filled ))
	local b="["
	for ((i=0; i<filled; i++)); do b+="="; done
	for ((i=0; i<empty; i++)); do b+="-"; done
	b+="]"
	printf "${LIGHTBLUE}%s${NC}" "$b"
}

# Section header
section() {
	printf "\n${CYAN}${BOLD}  %-${W}s${NC}\n" "$1"
	printf "${CYAN}  "
	printf '%0.s-' $(seq 1 $W)
	printf "${NC}\n"
}

# ─────────────────────────────────────────────
# DRAW
# ─────────────────────────────────────────────
draw() {
	local sid="$1"

	# ── Fetch ──
	local summary top_domains top_clients versions
	summary=$(api_get "stats/summary" "$sid")
	top_domains=$(api_get "stats/top_domains?blocked=true&count=5" "$sid")
	top_clients=$(api_get "stats/top_clients?count=5" "$sid")
	versions=$(api_get "info/version" "$sid")

	# ── Parse summary ──
	local queries blocked percent gravity
	queries=$(json_val "$summary" "queries")
	blocked=$(json_val "$summary" "blocked")
	gravity=$(json_val "$summary" "gravity_size")
	queries=${queries:-0}
	blocked=${blocked:-0}
	if [[ "$queries" -gt 0 ]]; then
		percent=$(awk "BEGIN {printf \"%.1f\", $blocked/$queries*100}")
	else
		percent="0.0"
	fi

	# ── Parse versions (nested: version.core.local.version) ──
	local ph_ver ftl_ver
	ph_ver=$(echo "$versions"  | grep -o '"core":{.*' | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4)
	ftl_ver=$(echo "$versions" | grep -o '"ftl":{.*'  | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4)
	ph_ver=${ph_ver:-n/a}
	ftl_ver=${ftl_ver:-n/a}

	# ── System info ──
	local sys_uptime ram_used ram_total ram_pct disk_used disk_total disk_pct
	sys_uptime=$(uptime -p 2>/dev/null | sed 's/up //')
	ram_used=$(free -m  | awk '/^Mem:/{print $3}')
	ram_total=$(free -m | awk '/^Mem:/{print $2}')
	ram_pct=$(awk "BEGIN {printf \"%d\", ${ram_used:-0}/${ram_total:-1}*100}")
	disk_used=$(df -BG  / | awk 'NR==2{gsub("G","",$3); print $3}')
	disk_total=$(df -BG / | awk 'NR==2{gsub("G","",$2); print $2}')
	disk_pct=$(df /        | awk 'NR==2{gsub("%","",$5); print $5}')

	# ── Render ──
	tput cup 0 0

	# Header box (pure ASCII, fixed width = W+2)
	local sep
	sep=$(printf '%0.s-' $(seq 1 $((W+2))))
	local title="Pi-hole Status Report - Live Dashboard"
	local sub
	sub="$(date '+%a %d %b %Y  %H:%M:%S')    [refresh: ${REFRESH}s]"

	printf "${YELLOW}${BOLD}+%s+${NC}\n"                          "$sep"
	printf "${YELLOW}${BOLD}|${NC} ${BOLD}%-${W}s${NC} ${YELLOW}${BOLD}|${NC}\n" "$title"
	printf "${YELLOW}${BOLD}|${NC} ${CYAN}%-${W}s${NC} ${YELLOW}${BOLD}|${NC}\n" "$sub"
	printf "${YELLOW}${BOLD}+%s+${NC}\n"                          "$sep"

	# VERSIONS
	section "VERSIONS"
	printf "  ${LIGHTBLUE}${BOLD}%-22s${NC} %s\n"  "Pi-hole:"       "$ph_ver"
	printf "  ${LIGHTBLUE}${BOLD}%-22s${NC} %s\n"  "FTL:"           "$ftl_ver"
	printf "  ${LIGHTBLUE}${BOLD}%-22s${NC} %s\n"  "System uptime:" "$sys_uptime"

	# SERVICES
	section "SERVICES"
	printf "  ${LIGHTBLUE}${BOLD}%-22s${NC} [%b]\n"  "pihole-FTL:"  "$(service_status pihole-FTL)"
	printf "  ${LIGHTBLUE}${BOLD}%-22s${NC} [%b]\n"  "cron:"        "$(service_status cron)"

	# QUERIES TODAY
	section "QUERIES TODAY"
	printf "  ${LIGHTBLUE}${BOLD}%-22s${NC} %s\n"         "Total queries:"   "$queries"
	printf "  ${LIGHTBLUE}${BOLD}%-22s${NC} %s  (%s%%)\n" "Blocked:"         "$blocked" "$percent"
	printf "  ${LIGHTBLUE}${BOLD}%-22s${NC} "              "Block rate:"
	bar "$blocked" "$queries"; echo
	printf "  ${LIGHTBLUE}${BOLD}%-22s${NC} %s\n"         "Gravity domains:" "${gravity:-n/a}"

	# SYSTEM RESOURCES
	section "SYSTEM RESOURCES"
	printf "  ${LIGHTBLUE}${BOLD}%-22s${NC} %4s MB / %4s MB  (%3s%%)  " "RAM:"      "$ram_used"  "$ram_total" "$ram_pct"
	bar "$ram_pct" 100; echo
	printf "  ${LIGHTBLUE}${BOLD}%-22s${NC} %4s GB / %4s GB  (%3s%%)  " "Disk (/):" "$disk_used" "$disk_total" "$disk_pct"
	bar "$disk_pct" 100; echo

	# TOP 5 BLOCKED DOMAINS
	section "TOP 5 BLOCKED DOMAINS"
	local domains_found=0
	while IFS= read -r line; do
		local domain count
		domain=$(echo "$line" | grep -o '"domain":"[^"]*"' | cut -d'"' -f4)
		count=$(echo  "$line" | grep -o '"count":[0-9]*'   | cut -d':' -f2)
		[[ -z "$domain" ]] && continue
		printf "  ${RED}>${NC} %-40s %s hits\n" "$domain" "$count"
		((domains_found++))
	done < <(echo "$top_domains" | grep -o '{[^}]*"domain":"[^"]*"[^}]*}')
	[[ $domains_found -eq 0 ]] && printf "  ${YELLOW}No data available${NC}\n"

	# TOP 5 CLIENTS
	section "TOP 5 CLIENTS"
	local clients_found=0
	while IFS= read -r line; do
		local ip name count label
		ip=$(echo    "$line" | grep -o '"ip":"[^"]*"'   | cut -d'"' -f4)
		name=$(echo  "$line" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
		count=$(echo "$line" | grep -o '"count":[0-9]*' | cut -d':' -f2)
		[[ -z "$ip" ]] && continue
		label="${name:-$ip}"
		printf "  ${LIGHTBLUE}>${NC} %-40s %s queries\n" "$label" "$count"
		((clients_found++))
	done < <(echo "$top_clients" | grep -o '{[^}]*"ip":"[^"]*"[^}]*}')
	[[ $clients_found -eq 0 ]] && printf "  ${YELLOW}No data available${NC}\n"

	printf "\n${CYAN}  "
	printf '%0.s-' $(seq 1 $W)
	printf "${NC}\n"
	printf "  ${ITALIC}Press Ctrl+C to exit${NC}\n"
}

# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────
if [[ ! "${EUID}" -eq 0 ]]; then
	echo && echo -e "${RED}${BOLD}✗ Error:${NC} ${RED}This script requires elevated privileges to run.${NC}"
	echo -e "${YELLOW}${BOLD}➜ Solution:${NC} ${YELLOW}Please restart as root user or with sudo command.${NC}" && echo
	sleep 1 && exit 1
fi

SID=$(get_sid)

tput clear
tput civis

trap 'tput cnorm; tput clear; echo -e "${YELLOW}Goodbye!${NC}"; echo; exit 0' INT TERM

while true; do
	draw "$SID"
	sleep "$REFRESH"
done
