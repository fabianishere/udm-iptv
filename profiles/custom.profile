#!/bin/sh -e
# Script to configure custom profile
#
# Copyright (C) 2022 Fabian Mastenbroek.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

P_STATE=1
while true; do
    case "$P_STATE" in
    0)  # Ensure going back from initial step is harmless
        P_STATE=1
        continue
        ;;
    1)  # Ask whether IPTV traffic is carried over separate VLAN
        db_input high udm-iptv/wan-vlan-separate || true
        ;;
    2)  # If IPTV traffic is carried over a separate VLAN, ask which ID
        db_get udm-iptv/wan-vlan-separate
        if [ "$RET" = false ]; then
            # IPTV traffic is on native VLAN
            db_set udm-iptv/wan-vlan 0
            # Disable DHCP by default
            db_set udm-iptv/wan-dhcp false

            db_get udm-iptv/wan-port
            db_subst udm-iptv/wan-interface choices "$(_if_inet_list_upper "/sys/class/net/$RET" | sed ':a;N;s/\n/, /;ba')"
            db_input high udm-iptv/wan-interface || true
        else
            # WAN port is same as WAN interface
            db_get udm-iptv/wan-port
            db_set udm-iptv/wan-interface "$RET"

            # Enable DHCP by default
            db_set udm-iptv/wan-dhcp true

            # Configure VLAN ID
            db_input high udm-iptv/wan-vlan || true
        fi
        ;;
    3)
        db_get udm-iptv/wan-vlan-separate
        if [ "$RET" = true ]; then
            # Configure VLAN interface name
            db_input low udm-iptv/wan-vlan-interface || true
        fi
        ;;
    4)  # Configure MAC address of VLAN interface
        db_input low udm-iptv/wan-vlan-mac || true
        ;;
    5)  # Configure WAN ranges
        db_input high udm-iptv/wan-ranges || true
        ;;
    6)  # Override DHCP
        db_input low udm-iptv/wan-dhcp || true
        ;;
    7)  # Configure DHCP options
        db_get udm-iptv/wan-dhcp
        if [ "$RET" = true ]; then
            db_set udm-iptv/wan-static-ip ""
            db_input high udm-iptv/wan-dhcp-options || true
        else
            db_input low udm-iptv/wan-static-ip || true
        fi
        ;;
    8)  # Complete configuration
        break
        ;;
    *)  # unknown state
        echo "Unknown configuration state: $STATE" >&2
        exit 2
        ;;
    esac
    if db_go; then
        P_STATE=$((P_STATE + 1))
    else
        P_STATE=$((P_STATE - 1))
    fi
done