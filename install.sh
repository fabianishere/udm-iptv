#!/bin/sh
# Script for installing the IPTV container
#
# Copyright (C) 2021 Fabian Mastenbroek.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

if ! command -v unifi-os > /dev/null 2>&1; then
    echo "Make sure you run this command from UbiOS (and not UniFi OS)"
    exit 1
elif [ ! -d /mnt/data/on_boot.d/ ]; then
    echo "Make sure you have installed the on-boot-script on your device"
    echo "See https://github.com/boostchicken/udm-utilities/tree/master/on-boot-script"
    exit
fi

UDM_TYPE=$(grep -q "UDMPRO" /etc/board.info && echo "UDMP" || echo "UDMB")

# Helper functions to display colors in terminal
_ansi() {
    escape="\e[$1m"
    shift
    if [ -z ${NO_COLOR+x} ]; then
        printf "%b%s\e[0m" "$escape" "$*"
    else
        printf "%s" "$*"
    fi
}

_question()  {
    _ansi 1 "$@"
    printf "\n"
}

_warning()  {
    _ansi 1 "$(_ansi 31 "Warning: ")"
    echo "$@"
}

# Extract the IPv4 address of the specified interface
_if_inet_addr() {
    ip addr show dev "$1" | awk '$1 == "inet" { sub("/.*", "", $2); print $2 }'
}

# Extract the VLAN id of an interface
_if_vlan_id() {
     awk -F ' *\\| *' "\$1 == \"$1\" { print \$2 }" /proc/net/vlan/config
}

# Print the specified list of interfaces
_if_print_all() {
   n=1
   for interface in "$@"; do
       vlan_id=$(_if_vlan_id "$interface")
       inet_addr=$(_if_inet_addr "$interface")

       vlan_fmt=${vlan_id:+"(VLAN $vlan_id)"}
       printf "  %d: %-8s %-12s [IPv4 Address: %s]\n" "$n" "$interface" "$vlan_fmt" "${inet_addr:-None}"
       n=$(( n + 1 ))
   done
}

# Prompt the user for the WAN port to use
# This step is used to identify the port on which the WAN traffic enters the
# device.
_prompt_wan() {
    WAN_PORTS=$(test "$UDM_TYPE" = "UDMP" && echo "eth8 eth9" || echo "eth4")

    _question "What is your WAN port?"

    if [ "$UDM_TYPE" = "UDMP" ]; then
        n=3
        echo "  1. eth8 (WAN 1, RJ45)"
        echo "  2. eth9 (WAN 2, SFP+)"
    else
        n=2
        echo "  1. eth4 (WAN 1)"
    fi

    while true; do
        # shellcheck disable=SC2039
        read -r -p "Enter WAN port [default: $WAN_INTERFACE]: "
        if [ -z "$REPLY" ]; then
            break
        elif [ -d "/sys/class/net/$REPLY" ]; then
            WAN_INTERFACE="$REPLY"
            break
        elif [ "$REPLY" -eq "$REPLY" ] 2>/dev/null; then
            selection=$(echo "$WAN_PORTS" | cut -d" " -f"$REPLY")
            if [ -n "$selection" ]; then
                WAN_INTERFACE="$selection"
                break
            else
                echo "Invalid selection $REPLY"
            fi
        else
            echo "Invalid WAN port $REPLY"
        fi
    done
}

# Prompt the user for the WAN VLAN for the IPTV network
# This step is used to identify whether IPTV traffic is carried over a separate
# VLAN or is carried with the other WAN traffic.
_prompt_wan_vlan() {
    # Verify whether the chosen WAN interface is already a VLAN interface.
    # This means we don't have to ask for a separate VLAN
    vlan=$(_if_vlan_id "$WAN_INTERFACE")
    if [ -n "$vlan" ]; then
        return
    fi

    prompt_msg=$(_ansi 1 "Is IPTV traffic carried over a separate VLAN?")
    while true; do
        # shellcheck disable=SC2039
        read -r -p "$prompt_msg ([Y]es or [N]o): "
        case $(echo "$REPLY" | tr '[:upper:]' '[:lower:]') in
            y|yes)
                custom_vlan="yes"
                break
                ;;
            n|no)
                custom_vlan="no"
                break
                ;;
        esac
    done

    # IPTV traffic is carried over a separate VLAN
    if [ "$custom_vlan" = "yes" ]; then
        WAN_VLAN="4"

        while true; do
            # shellcheck disable=SC2039
            read -r -p "Enter VLAN ID [default: $WAN_VLAN]: "
            if [ -z "$REPLY" ]; then
                break
            elif [ "$REPLY" -eq "$REPLY" ] 2>/dev/null; then
                WAN_VLAN="$REPLY"
                break
            else
                echo "Invalid VLAN ID $REPLY"
            fi
        done

        return
    fi

    WAN_VLAN="0"

    # IPTV traffic is carried in same VLAN as WAN traffic.
    # However, some setups carry the actual WAN traffic using PPPoE or over
    # a separate VLAN.
    # Let the user decide which interface to use.
    WAN_INTERFACES=$(find /sys/class/net -name "$WAN_INTERFACE" -exec basename {} \; | sort)
    PPP_INTERFACES=$(find /sys/class/net -name 'ppp?' -exec basename {} \;)
    ALL_WAN_INTERFACES="$WAN_INTERFACES $PPP_INTERFACES"

    _question "Which WAN interface carries your network traffic?"
    _if_print_all $ALL_WAN_INTERFACES

    while true; do
        # shellcheck disable=SC2039
        read -r -p "Enter WAN interface [default: $WAN_INTERFACE]: "
        if [ -z "$REPLY" ]; then
            break
        elif [ -d "/sys/class/net/$REPLY" ]; then
            WAN_INTERFACE="$REPLY"
            break
        elif [ "$REPLY" -eq "$REPLY" ] 2>/dev/null; then
            selection=$(echo "$ALL_WAN_INTERFACES" | cut -d" " -f"$REPLY")
            if [ -n "$selection" ]; then
                WAN_INTERFACE="$selection"
                break
            else
                echo "Invalid selection $REPLY"
            fi
        else
            echo "Invalid WAN interface $REPLY"
        fi
    done

    # Verify whether selected WAN interface has an IP address.
    # In many cases, having no IP address means that the user selected the
    # wrong interface.
    inet_addr=$(_if_inet_addr "$WAN_INTERFACE")
    if [ -z "$inet_addr" ]; then
        _warning "WAN interface $WAN_INTERFACE has no IP address. Make sure you have selected the correct interface."
    fi
}

# Prompt the user for the WAN ranges
_prompt_wan_ranges() {
    _question "Which addresses are used for IPTV traffic?"

    # shellcheck disable=SC2039
    read -r -p "Enter WAN ranges [default: $WAN_RANGES]: "
    if [ -n "$REPLY" ]; then
        WAN_RANGES="$REPLY"
    fi
}

# Prompt the user for the LAN configuration
_prompt_lan() {
    ALL_LAN_INTERFACES=$(find /sys/class/net -name "br*" -exec basename {} \; | sort)

    _question "Which LANs are allowed to receive IPTV traffic?"
    _if_print_all $ALL_LAN_INTERFACES

    while true; do
        # shellcheck disable=SC2039
        read -r -p "Enter LAN interfaces separated by spaces [default: $LAN_INTERFACES]: "
        if [ -z "$REPLY" ]; then
            break
        fi

        LAN_INTERFACES="" # Remove default LAN interface
        error=""
        for interface in $REPLY; do
            if [ "$interface" -eq "$interface" ] 2>/dev/null; then
                selection=$(echo "$ALL_LAN_INTERFACES" | sed -n "$interface"p )
                if [ -n "$selection" ]; then
                    LAN_INTERFACES="$LAN_INTERFACES $selection"
                else
                    echo "Invalid selection $interface"
                    error="yes"
                    break
                fi
            elif [ -d "/sys/class/net/$interface" ]; then
                LAN_INTERFACES="$LAN_INTERFACES $interface"
            else
                echo "Invalid LAN interface $interface"
                error="yes"
                break
            fi
        done

        if [ -z "$error" ]; then
            # Remove duplicate interfaces
            LAN_INTERFACES=$(echo "$LAN_INTERFACES" | tr " " "\n" | sort -u | xargs)
            break
        fi
    done
}

# Prompt the user for immediately starting the container.
_prompt_start() {
    prompt_msg=$(_ansi 1 "Should the container be started immediately?")
    while true; do
        # shellcheck disable=SC2039
        read -r -p "$prompt_msg ([Y]es or [N]o): "
        case $(echo "$REPLY" | tr '[:upper:]' '[:lower:]') in
            y|yes) break ;;
            n|no)  return ;;
        esac
    done

    echo "Starting container..."
    /mnt/data/on_boot.d/15-iptv.sh
    # Show the logs for 10 seconds
    timeout -s INT 10 podman logs -f iptv
}

# Prompt the user for the LAN configuration
_show_config() {
    _question "Generated the following configuration:"
    printf "  WAN Interface:      %s\n" "$WAN_INTERFACE"
    printf "  IPTV VLAN (WAN):    %s\n" "$WAN_VLAN"
    printf "  IPTV Ranges (WAN):  %s\n" "$WAN_RANGES"
    printf "  LAN Interfaces:     %s\n" "$LAN_INTERFACES"
}

# Create the boot script at the specified location
_create_config() {
    tee  "$1" <<EOF >/dev/null
## IPTV Configuration
IPTV_WAN_INTERFACE="$WAN_INTERFACE"
IPTV_WAN_RANGES="$WAN_RANGES"
IPTV_WAN_VLAN="$WAN_VLAN"
IPTV_WAN_DHCP_OPTIONS="-O staticroutes -V IPTV_RG"
IPTV_LAN_INTERFACES="$LAN_INTERFACES"
IPTV_IGMPPROXY_ARGS=""

## Diagnostics
if [ "\$1" == "diagnose" ]; then
    if [ "\$IPTV_WAN_VLAN" -ne 0 ]; then
        target="iptv"
    else
        target="\$IPTV_WAN_INTERFACE"
    fi

    echo "Please share the following output with the developers:"
    echo "=== Configuration ==="
    echo "WAN Interface: \$IPTV_WAN_INTERFACE"
    echo "WAN Ranges: \$IPTV_WAN_RANGES"
    echo "WAN VLAN: \$IPTV_WAN_VLAN"
    echo "LAN Interfaces: \$IPTV_LAN_INTERFACES"

    echo "=== IP Link and Route ==="
    ip -4 addr show dev \$target
    ip route show dev \$target

    echo "=== Container Logs ==="
    podman logs iptv | tail

    exit
fi

## Boot script
if podman container exists iptv; then
  echo "Removing existing IPTV container..."
  podman rm -f iptv > /dev/null 2>&1
fi

podman run --network=host --privileged \\
    --name iptv -i -d --restart on-failure:5 \\
    -e IPTV_WAN_INTERFACE="\$IPTV_WAN_INTERFACE" \\
    -e IPTV_WAN_RANGES="\$IPTV_WAN_RANGES" \\
    -e IPTV_WAN_VLAN="\$IPTV_WAN_VLAN" \\
    -e IPTV_WAN_DHCP_OPTIONS="\$IPTV_WAN_DHCP_OPTIONS" \\
    -e IPTV_LAN_INTERFACES="\$IPTV_LAN_INTERFACES" \\
    -e IPTV_LAN_RANGES="" \\
    fabianishere/udm-iptv \$IPTV_IGMPPROXY_ARGS > /tmp/udm-iptv.txt 2>&1
res="\$?"
if [ "\$res" -ne 0 ]; then
    echo "Failed to launch IPTV container: error \$res."
    echo "See /tmp/udm-iptv.txt for the error log."
fi
exit \$res
EOF
    chmod +x /mnt/data/on_boot.d/15-iptv.sh
}

# Default values
WAN_INTERFACE=$(test "$UDM_TYPE" = "UDMP" && echo "eth8" || echo "eth4")
WAN_VLAN="0"
WAN_RANGES="213.75.0.0/16 217.166.0.0/16"
LAN_INTERFACES="br0"

if [ "$INTERACTIVE" != "no" ]; then
    _prompt_wan
    _prompt_wan_vlan
    _prompt_wan_ranges
    _prompt_lan
fi

_show_config
target=/mnt/data/on_boot.d/15-iptv.sh
_create_config "$target"
echo "IPTV boot script successfully installed at $target"
echo "See https://github.com/fabianishere/udm-iptv/blob/master/README.md for more information"

if [ "$INTERACTIVE" != "no" ]; then
    _prompt_start
fi
