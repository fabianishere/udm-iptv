#!/bin/sh -e
# Profile for Vivo GVT (BR)
#
# Copyright (C) 2022 Fabian Mastenbroek.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

db_get udm-iptv/wan-port
db_set udm-iptv/wan-interface "$RET"

db_set udm-iptv/wan-vlan 4000
db_set udm-iptv/wan-ranges "0.0.0.0/0"
db_set udm-iptv/wan-dhcp false
db_set udm-iptv/wan-static-ip "10.0.0.1/32"
#db_set udm-iptv/vod="true"
#db_set udm-iptv/vod-vlan=602
#db_set udm-iptv/vod-wan-ranges="172.28.0.0/14 177.16.0.0/16 200.161.71.0/24 201.0.52.0/23"
#db_set udm-iptv/vod-wan-dhcp-options "-O staticroutes -V TEF_IPTV"

db_subst udm-iptv/profile-note note "Set DNS servers to 177.16.30.67 and 177.16.30.7 for internal IPTV network"
db_input medium udm-iptv/profile-note || true
