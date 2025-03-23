#!/bin/sh -e
# Profile for VDF (PT)
#
# Copyright (C) 2025 Fred Moura.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

db_get udm-iptv/wan-port
db_set udm-iptv/wan-interface "$RET"

db_set udm-iptv/wan-vlan 105
db_set udm-iptv/wan-ranges "10.20.0.0/16"
db_set udm-iptv/wan-dhcp false
