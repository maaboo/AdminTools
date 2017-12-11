#!/bin/bash

# Gets hardware info from ESXi

# Requirements: Connection to ESXi hosts should be passwordless

# Scripts convert and round MHz to GHz, bytes of RAM to gigabytes,
# any notation of KB, MB and GB with four and more digits to the shorest with
# certain digits after point. For instance 8584668 MB -> 8.2 TB.

# Author: Grigory Kireev, https://github.com/maaboo

# Free to use, redistribute and modify without
# permission. If you want to show respect to the author
# please keep this commented block intact.

# Disclaimer:

# This script is provided without any guarantees and
# responsibilities. Person who runs the script should
# fully understand what commands will be executed and
# what result is expected.       


scriptname=`basename "$0"` ; hv=$1 ; request=$2 ; hddoption=$3
hpssacli='/opt/hp/hpssacli/bin/hpssacli' ; dontclean=0

read -r -d '' usage << EOF
\nUsage:

$scriptname <host name FQDN> <request> [disk option]

  Where <request> is one of:
  
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

[disk option] is used along with hdd request and it's one of:

  raidctlr<controller number> - for example for slot 0: raidctlr0 
  jbod\n

EOF

re_digit="^[0-9]+([.,]?[0-9]+)?$" ; re_unit="[0-9]+([.,]?[0-9]+)?\s*[KMGTPE]?"
re_point="[.]{1}" ; re_startwithnumber="^[0-9]+([.,]?[0-9]+)?"
re_digit_s="[^0-9. ]*$"
prefix_indexes=("" "K" "M" "G" "T" "P" "E" "Z" "Y")
stop_list=( "Asus 5900GSX" )

function printPrefixed() { # Prints number with preserved prefix and precision
  precision="${2:-0}"
  IFS=' ' read -r -a array <<< "$1"
  if [[ "${#array[@]}" -ge 2 ]];
  then number="${array[0]}" ; prefix="${array[1]}"
  else number="${array[0]}" ; prefix=""
  fi
  format="%."$precision"f" ; number=$(printf "$format" "$number")
  printf "%s" "$number $prefix"
}

function extractPart {
  digit_part=$(echo $1 | sed -e 's/'"$re_digit_s"'//g')
  letter_part=$(printf '%s' ${1//$digit_part/})
  case "$2" in
  number) printf "%s" "$digit_part" ;;
  suffix) printf "%s" "$letter_part" ;;
  esac
}

function roundUp() { printf "%.0f" "$1" ; }

function reduceString() {
# Reduces given number by the given base to the shortest notation using SI
# prefixes (including binary) for input and output
# Units should not start with starting prefix (capitalized K, M, etc) and
# should not contain spaces (like "light years"), so "Monty Pythons" is invalid.
# Usage: reduceString "$number" [base] [units] [starting prefix]
# Starting prefix: K - kilo, M - Mega, G - Giga, T - tera, P - peta, E - exa,
# Z - zetta, Y - yotta
# Samples:
# reduceString "$number" 1024 B T
# reduces given number by the base of 1024, where number means terabytes
# reduceString "$number" "" btc
# reduces given number by the base of 1000 (default), where number means btc
  
  whole="${1:-0}" ; base="${2:-1000}" ; units="${3:-""}" ;
  starting_prefix="${4:-""}" ; fraction=0 ; prefix_index=0
  for index in "${!prefix_indexes[@]}"; do
    if [[ "$starting_prefix" == "${prefix_indexes[index]}" ]];
    then prefix_index=$i; break; else prefix_index="1"
    fi
  done
  case "$base" in
    1000) prefix=($units {K,M,G,T,P,E,Z,Y}"$units") # Hz, KHz, MHz, etc
    ;;
    1024) prefix=($units {Ki,Mi,Gi,Ti,Pi,Ei,Zi,Yi}"$units") # KiB, MiB, etc
    # This piece is dirty and may produce weird results as MiHz.
    ;;
  esac
  while (($whole >= $base)); do
    fraction="$(printf ".%01d" $(($whole % $base * 100 / $base)))"
    whole=$(($whole / $base))
    if [ "$fraction" = ".0" ]; then fraction=0 ; fi
    if [[ $prefix_index < 8 ]]; then let prefix_index++; else break; fi
  done
  if [[ -z $fraction ]]; then
    printf "%s" "$whole ${prefix_indexes[$prefix_index]}$units"
  else
    printf "%s" "$whole$fraction ${prefix_indexes[$prefix_index]}$units"
  fi
}

function compactNumber {
# Converts something like "1234567.890" to "1.2 G"
# (depends on precision which is the second optional argument)
  precision="$2"; base="$3"
  if [[ $1 =~ $re_point ]]; then number=$(roundUp "$1"); else number="$1" ; fi
  out=$(reduceString "$number" "$base" "$units" "$prefix")
  out=$(printPrefixed "$out" "$precision")
  printf "%s" "$out"
}

function compactMixed { 
# Converts something like "Step: 1234567.890 MBps" to "Step: 1.23 TBps" 
# (depends on precision which is the second optional argument)
  input="$1" ; precision="$2" ; base="$3" ; field="" ; value=""; delimiter=":"
  if ! [[ $input =~ $re_startwithnumber ]]; then # Looks like: "Speed: 1 MBps"
    field=$(printf "%s" "$input" | cut -d "$delimiter" -f 1)"$delimiter"
    value=$(printf "%s" "$input" | cut -d "$delimiter" -f 2)
  fi
  suffix=$(extractPart "$value" suffix | sed 's/^ *//g')
  prefix_check=${suffix:0:1}
  for i in ${!prefix_indexes[@]}; do
    if [[ $prefix_check == ${prefix_indexes[$i]} ]]; then 
      units=$(printf "%s" "$suffix" | sed 's/^.//')
      prefix="$prefix_check"
      break
    else units="$suffix"; prefix=""
    fi
  done
  number=$(extractPart "$value" number); 
  if ! [[ $number =~ $re_startwithnumber ]]; then
    # It's not a number - print as is
    printf "%s" "$field$value"
    else
      # Round up any FP numbers 
      if [[ $input =~ $re_point ]]; then number=$(roundUp "$number")
      else number="$number"
      fi
    # Check for stop-list
    for ITEM in "${stop_list[@]}"; do
      if [[ $ITEM =~ $suffix ]]; then 
        value="$suffix"
      else
        value=$(reduceString "$number" "$base" "$units" "$prefix")
        value=$(printPrefixed "$value" "$precision")
      fi
    done
    printf "%s" "$field $value"	
  fi
}

function processStrings { 
  source_string=$1; re_interlinedelimiter=$2 ; re_intralinedelimiter=$3
  mapfile -t src_line_array <<<"$source_string"
  format_array=(); strings_array=()
  for line in "${src_line_array[@]}"; do
    substr_array=()
    if [[ $line =~ $re_intralinedelimiter ]]; then
      IFS="$re_intralinedelimiter" read -ra substr_array <<<"$line"
      strings_array+=( "${substr_array[@]}" )
      format_array+=( "${#substr_array[@]}" )
    else
      strings_array+=( "$line" )
      format_array+=(1)
    fi
  done
  for i in "${!strings_array[@]}"; do
    strings_array[$i]=$(compactMixed "${strings_array[$i]}" 1)
  done
  count=0; str=""
  for i in "${!src_line_array[@]}"; do
    for ((x=0; x<"${format_array[$i]}"; x++)); do
      if [[ $x -eq $((${format_array[$i]}-1)) ]]; then
        str+="${strings_array[$count]}"$'\n'
      else
        str+="${strings_array[$count]}""$re_intralinedelimiter"
      fi
      ((count++))
    done
  done
  printf '%s' "$str"
}

function displayUsage { printf "$usage\n" ; }

function helpUsage {
  while getopts ':h:' option; do
    case "$option" in h) displayUsage; esac
  done
}

function cleanUp {
# Removes quotes and unnecessary spaces from the given string
  retval=$(echo "$1" | sed -e "s/\"//g;s/\'//g;s/^[ \t]*//;s/[ \t]*$//")
  retval=$(echo "$retval" | awk '$1=$1')
  echo "$retval"
}

function getInfo {
case "$1" in
  mb_vendor)
    cmd='smbiosDump | grep -A 11 "'"Board Info:"'" | grep Manufacturer'
    cmd=$cmd'| cut -d "'":"'" -f 2 | sed '"'s/\\\\\"//g'"' | head -n 1'
  ;;
  mb_model)
    cmd='smbiosDump | grep -A 11 "'"Board Info:"'" | grep Product'
    cmd=$cmd'| cut -d "'":"'" -f 2 | sed '"'s/\\\\\"//g'"''
  ;;	
  cpu_model)
    cmd='vim-cmd hostsvc/hostsummary | grep cpuModel | cut -d '"'\"'"' -f2'
  ;;
  cpu_count)
    cmd='vim-cmd hostsvc/hosthardware | grep numCpuPackages'
    cmd=$cmd'| cut -d "'"="'" -f2 | sed '"'s/,//g;s/ //g'"''
  ;;
  cpu_core_count)
    cmd='vim-cmd hostsvc/hostsummary | grep numCpuCores'
    cmd=$cmd'| cut -d "'"="'" -f2 | sed '"'s/,//g;s/ //g'"''
  ;;
  cpu_frequency)
    cmd='vim-cmd hostsvc/hostsummary | grep cpuMhz '
    cmd=$cmd'| cut -d "'"="'" -f2 | sed '"'s/,//g;s/ //g'"''
  ;;
  ram_total)
    cmd='vim-cmd hostsvc/hostsummary | grep memorySize '
    cmd=$cmd'| cut -d "'"="'" -f2 | sed '"'s/,//g;s/ //g'"''
  ;;
  ram_type) 
    cmd='smbiosDump | grep -A 13 "'"Memory Device: "'" '
    cmd=$cmd'| egrep "'"^ {4}Type:"'" | cut -d "'":"'" -f 2 | sed '"'s/ //g'"''
    cmd=$cmd'| cut -d "'"("'" -f2 | cut -d "'")"'" -f1 | head -n 1'
  ;;
  ram_ecc)
    cmd='smbiosDump |grep -A 5 "'"Physical Memory Array"'" | grep ECC '
    cmd=$cmd'| cut -d "'":"'" -f 2 | sed '"'s/ //g'"' '
    cmd=$cmd'| cut -d "'"("'" -f2 | cut -d "'")"'" -f1 | head -n 1'
  ;;
  ram_slots_total)
    cmd='smbiosDump |grep -A 5 "'"Physical Memory Array"'" | grep Slots '
    cmd=$cmd'| cut -d "'":"'" -f 2 | sed '"'s/ //g'"' | head -n 1 '
  ;;
  ram_slots_busy)
  # Amount of occupied slots (divide this by number of occupied CPU sockets):
    cmd='smbiosDump | grep -A 13 "'"Memory Device: "'" '
    cmd=$cmd'| egrep "'"^ {4}Type:"'" | cut -d "'":"'" -f 2 '
    cmd=$cmd'| sed '"'s/ //g'"'' 
    cmd=$cmd'| cut -d "'"("'" -f2 | cut -d "'")"'" -f1 | wc -l'
  ;;
  ram_max)
    cmd='smbiosDump |grep -A 5 "'"Physical Memory Array"'" | grep Max '
    cmd=$cmd'| cut -d "'":"'" -f 2 | sed '"'s/[^0-9.]*\([0-9.]*\).*/\1/'"' '
    cmd=$cmd'| head -n 1 '
  ;;
  hdd)
    case "$hddoption" in
      jbod)
        cmd='esxcfg-scsidevs -l | grep -B 7 "'"Is Removable: false"'" '
        cmd=$cmd'| grep -B 3 -A 1 "'"\/vmfs\/devices\/disks/"'" '
        cmd=$cmd'| egrep -i "'"([M]odel|[D]isplay Name|[S]ize:)"'" '
        cmd=$cmd'| sed -r "'"s/Vendor: ATA {7}//g;s/Revis.*//g"'"'
      ;;
      raidctlr*)
        controller=$(echo "$hddoption" | sed 's/[^0-9.]*\([0-9.]*\).*/\1/')
        cmd=$hpssacli' ctrl slot='$controller' pd all show detail '
        cmd=$cmd'| grep -B 6 "[M]odel" | grep -A 6 "[S]ize" '
        cmd=$cmd'| egrep -i "([M]odel|[S]ize:)" '
        cmd=$cmd'| sed -r '"'s/Model: ATA {5}/Model: /g'"' | grep -v Native'
      # Swap lines - Model first, then size
        cmd=$cmd'| sed "N;s/\(.*\)\n\(.*\)/\2\n\1/"'
      ;;
      *)
      printf "\nERR: Wrong disk option.\n" ; displayUsage ; exit 1 ;;
    esac
  ;;
  *)
    printf "\nERR: Wrong argument provided.\n" ; displayUsage ; exit 1 ;;
esac
info=$(ssh root@"$hv" "$cmd")
printf "$info"
}

# Main

if [[ "$#" -ge 2 && "$#" -le 3 ]]; then
  if [[ "$#" -ne 3 && "$request" == "hdd" ]]; then
    printf "\nERR: Disk option is required when using hdd argument.\n"
    displayUsage
    exit 1
  fi
else
  printf "\nERR: Arguments mismatch.\n" ; displayUsage ; exit 1	
fi
out=$(getInfo "$request")
if [ $? -ne 0 ]; then printf "$out" ; exit 1 ; fi
# Output post processing
case "$request" in
  cpu_model)
    # Delete unnecessary trademarks, vendor names, words "CPU" and "processor"
    out=$(printf "%s" "$out" | sed 's/(R)//g;s/Intel//g;s/(tm)//g;s/AMD//g')
    out=$(printf "%s" "$out" | sed 's/CPU//g;s/Processor//g')
    # And frequency info
    out=$(printf "%s" "$out" | sed 's/@.*//g')
  ;;
  cpu_frequency)
    out=$(compactNumber "$out" "1" "1000")
  ;;
  ram_slots_busy)
    # Amount of occupied slots (divide this by number of occupied CPU sockets):
    sockets=$(getInfo cpu_count)
    out=$(( $out / $sockets ))
  ;;
  ram_total)
    out=$(compactNumber "$out" "0" "1024")
  ;;
  hdd)
  case "$hddoption" in
    jbod)
      out=$(printf "%s" "$out" | awk 'ORS=NR%3?",":"\n"')
      out=$(printf "%s" "$out" | sed 's/Serial Attached SCSI/SAS/g')
      out=$(printf "%s" "$out" | sed 's/LOGICAL VOLUME/Log. Vol./g')
      out=$(printf "%s" "$out" | sed 's/Display Name/Name/g')
      out=$(printf "%s" "$out" | sed -e 's/(naa.\{34\}//g')
	  out=$(processStrings "$out" "\n" ",")
      dontclean=0
    ;;
    raidctlr*)
      out=$(printf "%s" "$out" | awk 'ORS=NR%2?",":"\n"')
      lines=$(printf "%s" "$out" | wc -l)
      # Max lines in HDD. When exceeded - make one line of every 2
      if [ $lines -ge 6 ]; then
        out=$(printf "%s" "$out" | awk 'ORS=NR%2?"; ":"\n"')
      fi
      dontclean=1
    ;;
  esac
  ;;
esac
if [ $dontclean -eq 0 ]; then out=$(cleanUp "$out"); fi
printf "%s\n" "$out"
