#!/bin/sh -e
# Profile for MagentaTV (DE)
#
# Copyright (C) 2022 Fabian Mastenbroek.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

db_set udm-iptv/wan-interface "ppp0"

db_set udm-iptv/wan-vlan 0
db_set udm-iptv/wan-ranges "224.0.0.0/4 87.141.0.0/16 193.158.0.0/15"
db_set udm-iptv/wan-dhcp-options "-O staticroutes -V IPTV_RG"
