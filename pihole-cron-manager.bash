#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
LIGHTBLUE='\033[1;36m'
CYAN='\033[0;36m'
BOLD='\033[1m'
ITALIC='\033[3m'
NC='\033[0m' # No Color

CRON_FILE="/etc/cron.d/pihole_custom"
LOG_FILE="/var/log/pihole_updateGravity.log"

# ─────────────────────────────────────────────
show_current() {
	echo
	echo -e "${CYAN}${BOLD}Current cron configuration:${NC}"
	echo -e "${CYAN}────────────────────────────────────────────${NC}"
	if [[ -f "$CRON_FILE" ]]; then
		while IFS= read -r line; do
			[[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
			echo -e " ${LIGHTBLUE}${BOLD}▸${NC} ${LIGHTBLUE}$line${NC}"
		done < "$CRON_FILE"
	else
		echo -e " ${YELLOW}No custom cron file found.${NC}"
	fi
	echo -e "${CYAN}────────────────────────────────────────────${NC}"
	echo
}

# ─────────────────────────────────────────────
apply_cron() {
	echo
	echo -e "${LIGHTBLUE}${BOLD}Writing cron configuration to ${CRON_FILE}...${NC}"

	cat > "$CRON_FILE" <<EOF
########## CRON PIHOLE ##########
# Managed by pihole-cron-manager.bash
# updateGravity: Mon-Sat at 05:05
5 5 * * 1-6 root PATH="\$PATH:/usr/sbin:/usr/local/bin/" pihole updateGravity >${LOG_FILE} || cat ${LOG_FILE}
EOF

	if [[ $? -eq 0 ]]; then
		echo -e "${GREEN}${BOLD}✓ ${NC}${GREEN}Cron file written successfully!${NC}"
	else
		echo -e "${RED}${BOLD}✗ ${NC}${RED}Failed to write cron file!${NC}"
		exit 1
	fi

	echo -e "${LIGHTBLUE}${BOLD}Restarting cron service...${NC}"
	if systemctl restart cron 2>/dev/null || systemctl restart crond 2>/dev/null; then
		echo -e "${GREEN}${BOLD}✓ ${NC}${GREEN}Cron service restarted successfully!${NC}"
	else
		echo -e "${RED}${BOLD}✗ ${NC}${RED}Failed to restart cron service!${NC}"
		exit 1
	fi
}

# ─────────────────────────────────────────────
remove_cron() {
	echo
	if [[ -f "$CRON_FILE" ]]; then
		rm -f "$CRON_FILE"
		echo -e "${GREEN}${BOLD}✓ ${NC}${GREEN}Cron file removed successfully!${NC}"
		systemctl restart cron 2>/dev/null || systemctl restart crond 2>/dev/null
		echo -e "${GREEN}${BOLD}✓ ${NC}${GREEN}Cron service restarted.${NC}"
	else
		echo -e "${YELLOW}${BOLD}⚠ ${NC}${YELLOW}No cron file found to remove.${NC}"
	fi
	echo
}

# ─────────────────────────────────────────────
show_log() {
	echo
	if [[ -f "$LOG_FILE" ]]; then
		echo -e "${CYAN}${BOLD}Last updateGravity log (${LOG_FILE}):${NC}"
		echo -e "${CYAN}────────────────────────────────────────────${NC}"
		tail -n 30 "$LOG_FILE"
		echo -e "${CYAN}────────────────────────────────────────────${NC}"
	else
		echo -e "${YELLOW}${BOLD}⚠ ${NC}${YELLOW}Log file not found. Has updateGravity run yet?${NC}"
	fi
	echo
}

# ─────────────────────────────────────────────
run_now() {
	echo
	echo -e "${LIGHTBLUE}${BOLD}Running pihole updateGravity now...${NC}"
	echo -e "${YELLOW}Output will be saved to ${LOG_FILE}${NC}"
	echo
	pihole updateGravity | tee "$LOG_FILE"
	echo
	echo -e "${GREEN}${BOLD}✓ ${NC}${GREEN}updateGravity completed!${NC}"
	echo
}

# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────
tput clear

# ROOT CHECK
if [[ ! "${EUID}" -eq 0 ]]; then
	echo && echo -e "${RED}${BOLD}✗ Error:${NC} ${RED}This script requires elevated privileges to run.${NC}"
	echo -e "${YELLOW}${BOLD}➜ Solution:${NC} ${YELLOW}Please restart as root user or with sudo command.${NC}" && echo
	sleep 1 && exit 1
fi

echo
echo -e "${YELLOW}${BOLD} Pi-hole — Cron Manager ${NC}"
echo -e "${CYAN}Manage scheduled tasks for Pi-hole.${NC}"

while true; do
	show_current

	echo -e "${BOLD}What do you want to do?${NC}"
	echo
	echo -e " ${LIGHTBLUE}${BOLD}1)${NC} Apply / restore default cron ${ITALIC}(Mon-Sat 05:05 updateGravity)${NC}"
	echo -e " ${LIGHTBLUE}${BOLD}2)${NC} Remove cron file"
	echo -e " ${LIGHTBLUE}${BOLD}3)${NC} Show last updateGravity log"
	echo -e " ${LIGHTBLUE}${BOLD}4)${NC} Run updateGravity now manually"
	echo -e " ${RED}${BOLD}5)${NC} Exit"
	echo

	read -p "$(echo -e ${GREEN}${BOLD}Choose an option [1-5]: ${NC})" -n 1 -r
	echo

	case "$REPLY" in
		1)
			read -p "$(echo -e ${YELLOW}${BOLD}This will overwrite ${CRON_FILE}. Continue? \(Y/n\) ${NC})" -n 1 -r -s
			echo
			if [[ ! $REPLY =~ ^[Nn]$ ]]; then
				apply_cron
				echo
				echo -e "${CYAN}${BOLD}Schedule applied:${NC}"
				echo -e " ${LIGHTBLUE}${BOLD}▸${NC} updateGravity → ${LIGHTBLUE}Mon-Sat at 05:05${NC}"
				echo -e " ${LIGHTBLUE}${BOLD}▸${NC} Log → ${LIGHTBLUE}${LOG_FILE}${NC}"
			else
				echo && echo -e "${YELLOW}Operation cancelled.${NC}"
			fi
			;;
		2)
			read -p "$(echo -e ${RED}${BOLD}Remove ${CRON_FILE}? This will disable all Pi-hole cron jobs. \(Y/n\) ${NC})" -n 1 -r -s
			echo
			if [[ ! $REPLY =~ ^[Nn]$ ]]; then
				remove_cron
			else
				echo && echo -e "${YELLOW}Operation cancelled.${NC}"
			fi
			;;
		3)
			show_log
			;;
		4)
			read -p "$(echo -e ${YELLOW}${BOLD}Run updateGravity now? This may take a few minutes. \(Y/n\) ${NC})" -n 1 -r -s
			echo
			if [[ ! $REPLY =~ ^[Nn]$ ]]; then
				run_now
			else
				echo && echo -e "${YELLOW}Operation cancelled.${NC}"
			fi
			;;
		5)
			echo && echo -e "${YELLOW}Goodbye!${NC}" && echo
			exit 0
			;;
		*)
			echo && echo -e "${RED}${BOLD}✗ Invalid option.${NC}" && echo
			;;
	esac

	read -p "$(echo -e ${CYAN}Press any key to return to menu...${NC})" -n 1 -r -s
	tput clear
	echo
	echo -e "${YELLOW}${BOLD} Pi-hole — Cron Manager ${NC}"
	echo -e "${CYAN}Manage scheduled tasks for Pi-hole.${NC}"
done
