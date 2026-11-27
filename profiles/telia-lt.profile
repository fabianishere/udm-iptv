#!/bin/sh -e
# Profile for Telia (LT)
#
# Copyright (C) 2022 Fabian Mastenbroek.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

db_get udm-iptv/wan-port
db_set udm-iptv/wan-interface "$RET"

db_set udm-iptv/wan-vlan 6
db_set udm-iptv/wan-ranges "10.0.0.0/8, 85.206.131.0/24"
db_set udm-iptv/wan-dhcp true
db_set udm-iptv/wan-dhcp-options "-O staticroutes"
