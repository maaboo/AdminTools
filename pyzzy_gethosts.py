#!/usr/bin/python3

"""
pyzzy_gethosts - a part of Pyzzy - Python extension pack for Zabbix

Returns a list of hosts in the given host groups.

Requirements: Python 3.4 and higher with appropriate modules.

################ Usage ################

Unix shell:

path/to/gethosts.py --host-group "Group Name"

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
import argparse
import json

######## Constants

ZBXURL = "http://zabbix.local/zabbix"
ZBXLOGIN = "root"
ZBXPASSWORD = "root"
ZBXAPI = ZabbixAPI(ZBXURL, user=ZBXLOGIN, password=ZBXPASSWORD)

######## Parsing command line

parser = argparse.ArgumentParser(
    description="Returns a list of hosts in a Zabbix host group as "
                "JSON string to stdout."
    )
parser.add_argument(
    "--host-groups", nargs="+", type=str, required=True,
    help="name of Zabbix groups of hosts to extract names from separated"
         " by space"
    )

args = parser.parse_args()

######## Main part

def main():

    arg_hostgroups = args.host_groups
    zbx_groups = ZBXAPI.hostgroup.get(output=["itemid", "name"])
    py_hostnames = []

    for arg_hostgroup in arg_hostgroups:
        for zbx_group in zbx_groups:
            if arg_hostgroup == zbx_group["name"]:
                hosts = ZBXAPI.host.get(groupids=zbx_group["groupid"],
                                        output=["hostid", "name"])
                for host in hosts:
                    py_hostnames.append(host["name"])

    print(json.dumps(py_hostnames))

main()