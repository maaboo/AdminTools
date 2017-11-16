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
CLOCKEDTABLES="history history_text auditlog history_log alerts service_alarms acknowledges "
CLOCKEDTABLES=$CLOCKEDTABLES"history_uint events problem proxy_dhistory proxy_autoreg_host "
CLOCKEDTABLES=$CLOCKEDTABLES"history_str trends proxy_history trends_uint"
CLOCKEDTABLESSQL=$(echo "$CLOCKEDTABLES" | sed -e 's/ /,/g')
CLOCKEDTABLESSQL=$(echo "$CLOCKEDTABLES" | sed -r "s/[^,]+/'&'/g")

SQL="SET group_concat_max_len = 10240;"
SQL="${SQL} SELECT GROUP_CONCAT(table_name separator ' ')"
SQL="${SQL} FROM information_schema.tables WHERE table_schema='${MYSQLDATABASE}'"
SQL="${SQL} AND table_name NOT IN ($CLOCKEDTABLESSQL)"

NONCLOCKEDTABLES=$(mysql -u$MYSQLLOGIN -p$MYSQLPASSWORD -h$MYSQLHOST $MYSQLDATABASE -AN -e"${SQL}")

#Human readable time 	Seconds
#1 hour					3600 seconds
#1 day					86400 seconds
#1 week					604800 seconds
#1 month (30.44 days) 	2629743 seconds

SCRIPTNAME=`basename "$0"`

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

mysqldump -u$MYSQLLOGIN -p$MYSQLPASSWORD -h$MYSQLHOST $MYSQLDATABASE $NONCLOCKEDTABLES \
--force 2> "$PWD/$SCRIPTNAME_error.log" > $SAVEFILE &

mysqldump -u$MYSQLLOGIN -p$MYSQLPASSWORD -h$MYSQLHOST $MYSQLDATABASE $CLOCKEDTABLES \
--where="clock BETWEEN $BACKDATE and $CURRDATE" --force 2> "$PWD/$SCRIPTNAME_error.log" >> $SAVEFILE &

printf "WARNING: Errors are suppressed. Check script's log for details.\n"
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