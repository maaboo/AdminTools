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

# Initialize lastpipe for variable globalization (Bash > 4.2)                                         |

MYSQLLOGIN=root
MYSQLPASSWORD=root
MYSQLHOST=localhost
MYSQLDATABASE=zabbix
INTERVAL=3600
#Human readable time 	Seconds
#1 hour					3600 seconds
#1 day					86400 seconds
#1 week					604800 seconds
#2 weeks				1209600 seconds
#1 month (30.44 days) 	2629743 seconds
#1 year (365.25 days)	31557600 seconds
SAVEFILE=~/zabbix.slice.sql
CLOCKCOLUMN="clock"

function NLListToCSSQ {
# Converts list with new lines to comma separated, single quoted
	RETVAL=$(echo "$1" | sed -E ':a;N;$!ba;s/\r{0,1}\n/,/g')
	RETVAL=$(echo "$RETVAL" | sed 's/,$//')
	RETVAL=$(echo "$RETVAL" | sed -r "s/[^,]+/'&'/g")
	echo "$RETVAL"
}

function CSSQtoCSS {
# Converts comma separated, single quoted list to comma separated with spaces
# after comma
	RETVAL=$(echo "$1" | sed "s/'//g")
	RETVAL=$(echo "$RETVAL" | sed -e "s/,/, /g")
	echo "$RETVAL"
}

function SStoCS {
# Converts space separated list to comma separated with spaces after comma
	RETVAL=$(echo "$1" | sed -e "s/ /, /g")
	echo "$RETVAL"
}

function CStoSS {
# Converts comma separated list to space separated
	RETVAL=$(echo "$1" | sed -e "s/, / /g")
	echo "$RETVAL"
}

function SStoNL {
# Converts space separated list to new line separated
	RETVAL=$(echo "$1" | sed -E -e 's/[[:blank:]]+/\n/g')
	echo "$RETVAL"
}

function Progress {

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
}

# Get clocked tables

CLSQL="SELECT DISTINCT TABLE_NAME FROM INFORMATION_SCHEMA.COLUMNS"
CLSQL=$CLSQL" WHERE COLUMN_NAME IN ('"$CLOCKCOLUMN"')" 
CLSQL=$CLSQL" AND TABLE_SCHEMA='"$MYSQLDATABASE"';"

CLTBLS=$(mysql -u"$MYSQLLOGIN" -p"$MYSQLPASSWORD" -h"$MYSQLHOST" \
"$MYSQLDATABASE" -AN -e"${CLSQL}")
CLTBLS=$(NLListToCSSQ "$CLTBLS")

# Get non-clocked tables by exclusion

NONCLSQL="SET group_concat_max_len = 10240;"
NONCLSQL=$NONCLSQL" SELECT GROUP_CONCAT(table_name separator ' ')"
NONCLSQL=$NONCLSQL" FROM information_schema.tables" 
NONCLSQL=$NONCLSQL" WHERE table_schema='"$MYSQLDATABASE"'"
NONCLSQL=$NONCLSQL" AND table_name NOT IN ($CLTBLS)"

NONCLTBLS=$(mysql -u$MYSQLLOGIN -p$MYSQLPASSWORD -h$MYSQLHOST \
$MYSQLDATABASE -AN -e"${NONCLSQL}")

SCRIPTNAME=`basename "$0"`

CURRDATE=`date +"%s"`
BACKDATE=$(($CURRDATE-$INTERVAL))

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

CLTBLS=$(CSSQtoCSS "$CLTBLS")
CLTBLS=$(CStoSS "$CLTBLS")

printf "WARNING: Errors are redirected to script's error log.\n"
printf "\n"

echo -n >  $SAVEFILE

set +m
shopt -s lastpipe     

COUNT=0
NONCLTBLS=$(SStoNL "$NONCLTBLS")
printf "Dumping non-historical data:\n"
echo "$NONCLTBLS" | while read TBNAME ; \
do
	((COUNT++))
	mysqldump -u$MYSQLLOGIN -p$MYSQLPASSWORD -h$MYSQLHOST $MYSQLDATABASE \
	$TBNAME --force 2> \
	$PWD/$SCRIPTNAME_error.log >> $SAVEFILE &
	printf '%-40s' "$TBNAME"
	Progress
done
printf '%-40s' "Tables copied: $COUNT"
printf "\n"

COUNT=0
CLTBLS=$(SStoNL "$CLTBLS")
printf "Dumping historical data:\n"
echo "$CLTBLS" | while read TBNAME ; \
do
	((COUNT++))
	mysqldump -u$MYSQLLOGIN -p$MYSQLPASSWORD -h$MYSQLHOST $MYSQLDATABASE \
	$TBNAME --where="clock BETWEEN $BACKDATE and $CURRDATE" --force 2> \
	$PWD/$SCRIPTNAME_error.log >> $SAVEFILE &
	printf '%-40s' "$TBNAME"
	Progress
done
printf '%-40s' "Tables copied: $COUNT"
printf "\n"

printf "Dumping completed.\n"