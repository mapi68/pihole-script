#!/bin/bash


A="/var/www/html/admin/scripts/pi-hole/js/index.js"

valori() {
	echo
	sed -i 's/topItems/topItems='$f'/' $A
	sed -i 's/getQuerySources\&topClientsBlocked/getQuerySources='$t'\&topClientsBlocked='$b'/' $A
	echo "Now queries number are:"
	echo " $f 'Top Permitted Domains' and 'Top Blocked Domains'"
	echo " $t 'Top Clients (total)'"
	echo " $b 'Top Clients (blocked only)'"
	echo
	echo "Please refresh pihole web page from your browser!"
	echo
}

tput clear

# ROOT CHECK
if [[ ! "${EUID}" -eq 0 ]]; then
	echo && echo "Sorry but this script requires elevated privileges to run."
	echo "Please restart as root user or with sudo command." && echo
	sleep 1 && exit 1
fi

echo
echo "********************* Hello $USER! *********************"
echo
echo "This script changes queries number shown in pihole."
echo "Resetting to default value (10)..."
sed -i 's/getQuerySources=[0-9][0-9]\&topClientsBlocked=[0-9][0-9]/getQuerySources\&topClientsBlocked/' $A
sed -i 's/getQuerySources=&topClientsBlocked=/getQuerySources\&topClientsBlocked/' $A
sed -i 's/topItems=[0-9][0-9]/topItems/' $A
sed -i 's/topItems=/topItems/' $A

echo
read -p "Do you want to continue? (Y/n) " -n 1 -r -s
if [[ $REPLY =~ ^[Nn]$ ]]; then
	echo && echo && exit 1
fi
echo && echo

read -p "Do you want to load optimal values for medium pihole server? (Y/n) " -n 1 -r -s
if ! [[ $REPLY =~ ^[Nn]$ ]]; then
	f=15 && t=30 && b=$t
	echo && valori && exit 0
fi
echo && echo

echo "Please write 'Top Permitted Domains' and 'Top Blocked Domains' queries number (from 10 to 99):"
read f
if [ "$f" -gt 99 ] || [ "$f" -lt 10 ]; then
	echo "Value not correct!" && echo && exit 1
fi

echo
echo "Please write 'Top Clients (total)' queries number (from 10 to 99):"
read t
if [ "$t" -gt 99 ] || [ "$t" -lt 10 ]; then
	echo "Value not correct!" && echo && exit 1
fi

echo
echo "Please write 'Top Clients (blocked only)' queries number (from 10 to 99):"
read b
if [ "$b" -gt 99 ] || [ "$b" -lt 10 ]; then
	echo "Value not correct!" && echo && exit 1
fi

valori && echo && exit 0
