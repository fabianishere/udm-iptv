#!/bin/sh -e
# Profile for MEO (PT)
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
db_set udm-iptv/wan-ranges "10.159.0.0/16, 10.173.0.0/16, 194.65.46.0/23, 213.13.16.0/20, 224.0.0.0/4"
db_set udm-iptv/wan-dhcp false