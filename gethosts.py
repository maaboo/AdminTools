#!/usr/bin/python

# Returns a list of hosts in the given host groups
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

from pyzabbix import ZabbixAPI
import argparse

######## Constants

ZBXURL = "http://zabbix.local/zabbix"
ZBXLOGIN = "root"
ZBXPASSWORD = "root"
ZBXAPI = ZabbixAPI(ZBXURL, user=ZBXLOGIN, password=ZBXPASSWORD)

######## Parsing command line

parser = argparse.ArgumentParser(
    description="Returns a list of hosts in a Zabbix host group as "
                "Python list."
    )
parser.add_argument(
    "--host-groups", nargs="+", type=str, required=True,
    help="name of Zabbix groups of hosts to extract names from separated"
         " by space"
    )
parser.add_argument(
    "--show", action="store_true",
    help="Output script result to stdout"
    )
args = parser.parse_args()

######## Main part

def main():

    arg_hostgroups = args.host_groups
    zbx_groups = ZBXAPI.hostgroup.get(output=["itemid", "name"])
    hostnames = []

    for arg_hostgroup in arg_hostgroups:
        for zbx_group in zbx_groups:
            if arg_hostgroup == zbx_group["name"]:
                hosts = ZBXAPI.host.get(groupids=zbx_group["groupid"],
                                        output=["hostid", "name"])
                for host in hosts:
                    hostnames.append(host["name"])

    if args.show:
        print hostnames

    return hostnames

main()