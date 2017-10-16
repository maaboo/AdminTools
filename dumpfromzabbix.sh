#!/bin/bash

# Dump data from Zabbix for a certain period of time
#
# Author: Grigory Kireev, https://github.com/maaboo
#
# Free to use, redistribute and modify without
# permission. If you want to show respect to the author
# please keep this commented block intact.
#
# Disclaimer:
#
# This script is provided without any guarantees and
# responsibilities. Person who runs the script should
# fully understand what commands will be executed and
# what result is expected.

MYSQLLOGIN=root
MYSQLPASSWORD=root
MYSQLHOST=localhost
MYSQLDATABASE=zabbix
INTERVAL=604800
SAVEFILE=~/zabbix.slice.sql

#Human readable time 	Seconds
#1 hour					3600 seconds
#1 day					86400 seconds
#1 week					604800 seconds
#1 month (30.44 days) 	2629743 seconds

CURRDATE=`date +"%s"`
let BACKDATE=$CURRDATE-$INTERVAL

printf "\n"
printf "################################################################\n"
printf "# Script for dumping Zabbix database time slice                #\n"
printf "################################################################\n"
printf "\n"
printf "################################################################\n"
printf "From:	$(date -d @$BACKDATE)	\n"
printf "To:	$(date -d @$CURRDATE) \n"
printf "################################################################\n"
printf "\n"

mysqldump -u$MYSQLLOGIN -p$MYSQLPASSWORD -h$MYSQLHOST $MYSQLDATABASE \
--where="clock BETWEEN $BACKDATE and $CURRDATE" --force 2> /dev/null > $SAVEFILE &

printf "WARNING: Errors are suppressed due to absense 'clock' column in some tables.\n"
printf "\n"
printf "Working, please wait: \n"

# Progress indicator

pid=$! # Process Id of the previous running command

spin='-\|/'

i=0
while kill -0 $pid 2>/dev/null
do
  i=$(( (i+1) %4 ))
  printf "\r${spin:$i:1}"
  sleep .1
done

printf "\n"

printf "Dumping completed.\n"