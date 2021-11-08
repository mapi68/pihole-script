#!/bin/bash


WL=white.list

download() {
	wget -q -O /tmp/$WL "https://raw.githubusercontent.com/Zelo72/hosts/main/$WL"
	sed -i -e '/\#/d' -e '/^$/d' /tmp/$WL
	echo && echo "Building $WL..."
}

download
sed -i -n '/^[a-z]/p' /tmp/$WL
sort -o /tmp/$WL{,}
pihole -w `cat /tmp/$WL | tr '\n' ' '`

download
sed -i -n '/^\*/p' /tmp/$WL
sort -o /tmp/$WL{,}
pihole --white-regex `cat /tmp/$WL | tr '\n' ' '`

rm /tmp/$WL
