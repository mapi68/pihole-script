#!/bin/bash

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'      # Brighter blue
LIGHTBLUE='\033[1;36m' # Light blue/cyan
CYAN='\033[0;36m'
BOLD='\033[1m'
ITALIC='\033[3m'       # Italic text
NC='\033[0m' # No Color

A="/var/www/html/admin/scripts/js/index.js"

valori() {
	echo
	sed -i "s/\/api\/stats\/top_domains?blocked=true\";/\/api\/stats\/top_domains?blocked=true\&count=$f\";/" $A
	sed -i "s/\/api\/stats\/top_domains\";/\/api\/stats\/top_domains?blocked=false\&count=$f\";/" $A
	sed -i "s/\/api\/stats\/top_clients?blocked=true\";/\/api\/stats\/top_clients?blocked=true\&count=$h\";/" $A
	sed -i "s/\/api\/stats\/top_clients\";/\/api\/stats\/top_clients?blocked=false\&count=$h\";/" $A

	echo -e "${GREEN}${BOLD}✓ ${NC}${GREEN}${BOLD}Query numbers have been updated successfully!${NC}"
	echo -e " ${LIGHTBLUE}${BOLD}$f${NC} for 'Top Permitted Domains${NC}' and 'Top Blocked Domains${NC}'"
	echo -e " ${LIGHTBLUE}${BOLD}$h${NC} for 'Top Clients (total)${NC}' and 'Top Clients (blocked only)${NC}'"
	echo
	echo -e "${YELLOW}${BOLD} Action required: ${NC}Please refresh your Pi-hole web interface to see the changes!${NC}"
	echo
}

tput clear

# ROOT CHECK
if [[ ! "${EUID}" -eq 0 ]]; then
	echo && echo -e "${RED}${BOLD}✗ Error:${NC} ${RED}This script requires elevated privileges to run.${NC}"
	echo -e "${YELLOW}${BOLD}➜ Solution:${NC} ${YELLOW}Please restart as root user or with sudo command.${NC}" && echo
	sleep 1 && exit 1
fi

echo
echo -e "${YELLOW}${BOLD} Pi-hole v6 Query Number Modifier ${NC}"
echo -e "${CYAN}This script modifies the number of queries displayed in Pi-hole v6.${NC}"
echo -e "${YELLOW}Resetting to default value (10)...${NC}"
echo -e "${LIGHTBLUE}${BOLD}Downloading original file from Pi-hole repository...${NC}"
if wget -q -O $A https://github.com/pi-hole/web/raw/refs/heads/master/scripts/js/index.js; then
    echo -e "${GREEN}${BOLD}✓ ${NC}${GREEN}Successfully downloaded original index.js file${NC}"
else
    echo -e "${RED}${BOLD}✗ ${NC}${RED}Failed to download original file! Check your internet connection.${NC}"
    echo -e "${YELLOW}Script cannot continue without the original file.${NC}"
    exit 1
fi

echo
read -p "$(echo -e ${GREEN}${BOLD}Do you want to continue? \(Y/n\) ${NC})" -n 1 -r -s
if [[ $REPLY =~ ^[Nn]$ ]]; then
	echo && echo && exit 1
fi
echo && echo

read -p "$(echo -e ${GREEN}${BOLD}Do you want to load recommended values for a medium-sized Pi-hole server? \(Y/n\) ${NC})" -n 1 -r -s
if ! [[ $REPLY =~ ^[Nn]$ ]]; then
	f=15 && h=30
	echo && valori && exit 0
fi
echo && echo

echo -e "${LIGHTBLUE}${BOLD}Please enter the number of queries for:${NC}"
echo -e "${LIGHTBLUE}'Top Permitted Domains${NC}${LIGHTBLUE}' and 'Top Blocked Domains${NC}${LIGHTBLUE}' ${ITALIC}(from 10 to 99)${NC}${LIGHTBLUE}:${NC}"
read f
if [ "$f" -gt 99 ] || [ "$f" -lt 10 ]; then
	echo -e "${RED}${BOLD}✗ Invalid value!${NC} ${RED}Must be between 10 and 99.${NC}" && echo && exit 1
fi

echo -e "${LIGHTBLUE}${BOLD}Please enter the number of queries for:${NC}"
echo -e "${LIGHTBLUE}'Top Clients (total)${NC}${LIGHTBLUE}' and 'Top Clients (blocked only)${NC}${LIGHTBLUE}' ${ITALIC}(from 10 to 99)${NC}${LIGHTBLUE}:${NC}"
read h
if [ "$h" -gt 99 ] || [ "$h" -lt 10 ]; then
	echo -e "${RED}${BOLD}✗ Invalid value!${NC} ${RED}Must be between 10 and 99.${NC}" && echo && exit 1
fi

valori && echo && exit 0
