#!/bin/bash

# Gets hardware info from ESXi

# Requirements: Connection to ESXi hosts should be passwordless

SCRIPTNAME=`basename "$0"`
HV=$1
REQUEST=$2
HDDOPTION=$3
HPSSACLI='/opt/hp/hpssacli/bin/hpssacli'

function cleanUp {
# Removes quotes and unnecessary spaces from the given string
	RETVAL=$(echo "$1" | sed -e "s/\"//g")
	RETVAL=$(echo "$RETVAL" | sed -e "s/\'//g")
	RETVAL=$(echo "$RETVAL" | sed -e "s/^[ \t]*//")
	RETVAL=$(echo "$RETVAL" | sed -e "s/[ \t]*$//")
	echo "$RETVAL"
}

read -r -d '' USAGE << EOM
Usage:

$SCRIPTNAME <host name FQDN> <request> [hddoption]

Where request is one of:

mb_vendor - Motherboard vendor (sinlge line string)
mb_model - Motherboard model (sinlge line string)
cpu_model - CPU model (sinlge line string)
cpu_count - Amount of physical CPUs (integer string)
cpu_core_count - Amount of cores per physical CPU (integer string)
cpu_frequency - CPU frequency (max, MHz) (integer string)
ram_total - Total amount of RAM (integer string)
ram_type - DDR generation
ram_ecc - ECC support
ram_slots_total - Total RAM slots available
ram_slots_busy - Amount of occupied slots
ram_max - Maximum supported memory
hdd - HDD info (capacity, storage name, model)

and hddoption is one of:

raidctlr<controller number> - for example for slot 0: raidctlr0 
jbod

\n
EOM

# Help
while getopts ':h:' option; do
        case "$option" in
                h) echo "$USAGE"
        esac
done

if [ "$#" -ne 2 ]; then
	if [ "$REQUEST" != "hdd" ]; then
        printf "\n$USAGE"
        exit 1
	fi
fi

case "$REQUEST" in

mb_vendor)
	CMD='smbiosDump | grep -A 11 "'"Board Info:"'" | grep Manufacturer'
	CMD=$CMD'| cut -d "'":"'" -f 2 | sed '"'s/\\\\\"//g'"' | head -n 1'
	;;
mb_model)
	CMD='smbiosDump | grep -A 11 "'"Board Info:"'" | grep Product'
	CMD=$CMD'| cut -d "'":"'" -f 2 | sed '"'s/\\\\\"//g'"''
	;;	
cpu_model)
	CMD='vim-cmd hostsvc/hostsummary | grep cpuModel | cut -d '"'\"'"' -f2'
	;;
cpu_count)
	CMD='vim-cmd hostsvc/hosthardware | grep numCpuPackages'
	CMD=$CMD'| cut -d "'"="'" -f2 | sed '"'s/,//g;s/ //g'"''
	;;
cpu_core_count)
	CMD='vim-cmd hostsvc/hostsummary | grep numCpuCores'
	CMD=$CMD'| cut -d "'"="'" -f2 | sed '"'s/,//g;s/ //g'"''
		;;
cpu_frequency)
	CMD='vim-cmd hostsvc/hostsummary | grep cpuMhz '
	CMD=$CMD'| cut -d "'"="'" -f2 | sed '"'s/,//g;s/ //g'"''
		;;
ram_total)
	CMD='vim-cmd hostsvc/hostsummary | grep memorySize '
	CMD=$CMD'| cut -d "'"="'" -f2 | sed '"'s/,//g;s/ //g'"''
		;;
ram_type) 
	CMD='smbiosDump | grep -A 13 "'"Memory Device: "'" '
	CMD=$CMD'| egrep "'"^ {4}Type:"'" | cut -d "'":"'" -f 2 | sed '"'s/ //g'"'' 
	CMD=$CMD'| cut -d "'"("'" -f2 | cut -d "'")"'" -f1 | head -n 1'
		;;
ram_ecc)
	CMD='smbiosDump |grep -A 5 "'"Physical Memory Array"'" | grep ECC '
	CMD=$CMD'| cut -d "'":"'" -f 2 | sed '"'s/ //g'"' '
	CMD=$CMD'| cut -d "'"("'" -f2 | cut -d "'")"'" -f1 | head -n 1'
		;;
ram_slots_total)
	CMD='smbiosDump |grep -A 5 "'"Physical Memory Array"'" | grep Slots '
	CMD=$CMD'| cut -d "'":"'" -f 2 | sed '"'s/ //g'"''
		;;
ram_slots_busy)
# Amount of occupied slots (divide this by number of occupied CPU sockets):
	CMD='smbiosDump | grep -A 13 "'"Memory Device: "'" '
	CMD=$CMD'|  egrep "'"^ {4}Type:"'" | cut -d "'":"'" -f 2 | sed '"'s/ //g'"'' 
	CMD=$CMD'| cut -d "'"("'" -f2 | cut -d "'")"'" -f1 | wc -l'
		;;
ram_max)
	CMD='smbiosDump |grep -A 5 "'"Physical Memory Array"'" | grep Max '
	CMD=$CMD'| cut -d "'":"'" -f 2 | sed '"'s/[^0-9.]*\([0-9.]*\).*/\1/'"' '
	CMD=$CMD'| head -n 1 '
		;;
hdd)
	if [ "$#" -ne 3 ]; then
			printf "\nError: Disk option is required when using hdd argument\n"
			printf "\n$USAGE"
			exit 1
	fi
	case "$HDDOPTION" in
		jbod)
		CMD='esxcfg-scsidevs -l | grep -B 7 "'"Is Removable: false"'" '
		CMD=$CMD'| grep -B 3 -A 1 "'"\/vmfs\/devices\/disks/"'" '
		CMD=$CMD'| egrep -i "'"([M]odel|[D]isplay Name|[S]ize:)"'" '
		CMD=$CMD'| sed -r "'"s/Vendor: ATA {7}//g;s/Revis.*//g"'"'
		;;
		raidctlr*)
		CONTROLLER=$(echo $HDDOPTION | sed 's/[^0-9.]*\([0-9.]*\).*/\1/')
		CMD=$HPSSACLI' ctrl slot='$CONTROLLER' pd all show detail '
		CMD=$CMD'| grep -B 6 "[M]odel" | grep -A 6 "[S]ize" '
		CMD=$CMD'| egrep -i "([M]odel|[S]ize:)" '
		CMD=$CMD'| sed -r '"'s/Model: ATA {5}/Model: /g'"' | grep -v Native'
		;;
	esac
	;;
esac

OUTPUT=$(ssh root@$HV "$CMD")
OUTPUT=$(cleanUp "$OUTPUT")
printf "$OUTPUT"
