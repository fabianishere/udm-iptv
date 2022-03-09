#!/bin/sh -e
# Profile for Vivo SP (BR)
#
# Copyright (C) 2022 Fabian Mastenbroek.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

db_get udm-iptv/wan-port
db_set udm-iptv/wan-interface "$RET"

db_set udm-iptv/wan-vlan 20
db_set udm-iptv/wan-ranges "172.28.0.0/14, 201.0.52.0/23, 200.161.71.0/24, 177.16.0.0/16"
db_set udm-iptv/wan-dhcp false

db_subst udm-iptv/profile-note note "Set DNS servers to 177.16.30.67 and 177.16.30.7 for internal IPTV network"
db_input medium udm-iptv/profile-note || true