#!/usr/bin/python3

"""
pyzzy_runover - a part of Pyzzy - Python extension pack for Zabbix

Runs given command over list of hosts and prints results to stdout.

Requirements: Python 3.4 and higher with appropriate modules
Recommendations: pyzzy_gethosts

################ Usage ################

Inside data element:

param["'Group 1' 'Group N'", "'/path/to/command \$1 \$2..\$9'",
"'value2'..'value9'"]

It will run command with every host name returned from given groups
passed inside command as bash command line argument $1 and additional
set of arguments taken from value2..value9 and passed respectively
starting from $2 and up to $9. Total number of arguments supported is
exact as in Zabbix user parameter processing module. Please, pay
attention that parameters must be enclosed into single quotes ('')
in order to work and also special characters (like "$") must be
escaped. If you know how to avoid it - let me know.

Inside confuguration file (with pyzzy_gethosts):

UserParameter=param[*],./runover.py --hosts $(./gethosts.py
--host-group $1) --command $2 --positional_arguments $3

(without pyzzy_gethosts):

UserParameter=param[*],./runover.py --hosts $1
--command $2 --positional_arguments $3

################ Disclaimer and info ################

Author: Grigory Kireev, https://github.com/maaboo

Free to use, redistribute and modify without
permission. If you want to show respect to the author
please keep this commented block intact.

Disclaimer:

This script is provided without any guarantees and
responsibilities. Person who runs the script should
fully understand what commands will be executed and
what result is expected.
"""

from zabbix.api import ZabbixAPI
import sys # exiting
import argparse
import subprocess # bash execution
from subprocess import STDOUT
import json # argument processing
import re # input validation
import datetime # debugging

######## Constants

ZBXURL = "http://zabbix.local/zabbix"
ZBXLOGIN = "root"
ZBXPASSWORD = "root"
ZBXAPI = ZabbixAPI(ZBXURL, user=ZBXLOGIN, password=ZBXPASSWORD)

ERRWRONGHOSTNAME = "Wrong host names detected."
ERRFIRSTPLACEHOLDER = "Placeholder \$1 for host was not found."
ERRARGUMENTSMISMATCH = "Arguments do no match placeholders."
ERRBASH = "Bash shell execution error."
ERROTHER = "Uknown error."

PROCESSTIMEOUT=15

DEBUGLOG = "/opt/scripts/runover.py_debug"
ERRORLOG = "/opt/scripts/runover.py_error"

######## Parsing command line

parser = argparse.ArgumentParser(
    description="Runs given command over list of Zabbix hosts",
    formatter_class=argparse.RawTextHelpFormatter
    )

parser.add_argument(
    "--hosts", nargs="*", required=True,
    help="List of Zabbix hosts (as JSON list or space separated list)"
    )

parser.add_argument(
    "--command", nargs=1, required=True,
    help="Command to be executed over every host in the list"
    )

parser.add_argument(
    "--positional_arguments", nargs="*",
    help="OPTIONAL: Positional arguments (up to 7)\n"
         "to be passed inside command"
    )

parser.add_argument("--output-format", nargs=1, required=True,
                    help="Possible return values:\n\n"
                         "digit - 0 if all executed commands returned\n"
                         "0 otherwise 1\n\n"
                         "digitlist - comma separated values of return\n"
                         "codes of every executed command\n\n"
                         "hostlist - comma separated values of host\n"
                         "names where all executed commands returned\n"
                         "non-zero value\n\n"
                         "valuelist - comma separated values of\n"
                         "command return ($?)\n\n"
                         "combinedlist - comma separated values\n"
                         "{host name}:{value} where {value} is command\n"
                         "return ($?)"
                    )

args = parser.parse_args()

######## Main part

def is_valid_hostname(hostname):
# Code snippet from:
# https://stackoverflow.com/questions/2532053/validate-a-hostname-string
    if len(hostname) > 255:
        return False
    if hostname[-1] == ".":
        hostname = hostname[:-1] # strip exactly one dot from the right,
        #  if present
    allowed = re.compile("(?!-)[A-Z\d-]{1,63}(?<!-)$", re.IGNORECASE)
    return all(allowed.match(x) for x in hostname.split("."))

def count_regex_in_string(regular_expression, string):
#Returns amount of regex entries in the given string
    regex = re.compile(regular_expression)
    match = regex.findall(string)
    return len(match)

# Two functions below write messages to both stdout and file
# Use them for debugging this script

def debuglog(logstring,logfile):
    if __debug__:
        if logfile == "stdout":
            print("\nDEBUG:\n" + str(logstring))
        else:
            debug_command = ('echo "{0} : {1}" >> {2}'.
                             format(datetime.datetime.now(),
                                    logstring,logfile))
            subprocess.Popen(debug_command, shell=True)

def errorlog(errstring,errfile):
    if __debug__:
        if errfile == "stdout":
            print("\nERROR:\n" + str(errstring))
        else:
            err_command = ('echo "{0} : {1}" >> {2}'.
                             format(datetime.datetime.now(),
                                    errstring,errfile))
            subprocess.Popen(err_command, shell=True)

def main():

# Since argparse.add_argument converts JSON string to a list it becomes
# fully mess, so we need to clean up this list to extract pure names.

    hostnames = []
    badList = args.hosts
    translation_table = dict.fromkeys(map(ord, '"[],'), None)
    for badRecord in badList:
        hostnames.append(str(badRecord).translate(translation_table))

# validate for hostname

    for hostname in hostnames:
        if not is_valid_hostname(hostname):
            errorlog(ERRWRONGHOSTNAME, "stdout")
            sys.exit(1)
    command = str(args.command[0])
    positional_arguments = args.positional_arguments

# validate for positional arguments and placeholders

    if count_regex_in_string("[$][1]", command) == 0:
        errorlog(ERRFIRSTPLACEHOLDER, "stdout")
        sys.exit(1)

    if positional_arguments:
        if count_regex_in_string("[$][2-9]",command) \
                != len(positional_arguments):
            errorlog(ERRARGUMENTSMISMATCH, "stdout")
            sys.exit(1)

# replace placeholders with positional arguments
        for positional_argument in positional_arguments:
            # arguments starts with 1 and also we should skip the first
            index = positional_arguments.index(positional_argument) + 2
            command = command.replace('$%d' % index ,
                                          positional_argument)

# store result as dictionary {hostname}:{[exit code, bash output]}

    result = dict()

    for hostname in hostnames:
        exec_command = command
        exec_command = exec_command.replace('$%d' % 1, hostname)
        shell_process = subprocess.Popen(exec_command,
                                    shell=True,
                                    stdout=subprocess.PIPE,
                                    stderr=None
                                     )
        shell_returncode = shell_process.wait(10)
        shell_output = shell_process.communicate()[0].decode('utf-8').\
            rstrip("\n")
        result["{0}".format(hostname)] = \
        ["{0}".format(shell_returncode),
         "{0}".format(shell_output)]

    output_format = str(args.output_format[0])
    output_value = str()

    if output_format == "digit":
        for result_key,result_value in result.items():
            if result_value[0] != "0":
                output_value = "1"
            else:
                output_value = "0"

    elif output_format == "digitlist":
        _list = []
        for result_key, result_value in result.items():
            _list.append(result_value[0])
        output_value = ",".join(_list)

    elif output_format == "hostlist":
        _list = []
        for result_key,result_value in result.items():
            if result_value[0] != "0":
                _list.append(result_key)
        output_value = ",".join(_list)

    elif output_format == "valuelist":
        _list = []
        for result_key, result_value in result.items():
                _list.append(result_value[1])
        output_value = ",".join(_list)

    elif output_format == "combinedlist":
        _list = []
        for result_key, result_value in result.items():
                _list.append(result_key + ":"
                             + result_value[1])
        output_value = ",".join(_list)

    else:
        errorlog(ERROTHER,"stdout")

    print(output_value)

main()

