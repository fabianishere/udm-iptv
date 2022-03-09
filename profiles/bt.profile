#!/bin/sh -e
# Profile for BT (GB)
#
# Copyright (C) 2022 Fabian Mastenbroek.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

db_get udm-iptv/wan-port
db_set udm-iptv/wan-interface "$RET"

db_set udm-iptv/wan-vlan 0
db_set udm-iptv/wan-ranges "224.0.0.0/4, 109.159.247.0/24"
db_set udm-iptv/wan-dhcp false
db_set udm-iptv/wan-static-ip "10.20.30.1/24"