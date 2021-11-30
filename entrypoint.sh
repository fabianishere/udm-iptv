#!/bin/ash

IPTV_WAN_INTERFACE="${IPTV_WAN_INTERFACE:-eth8}"
IPTV_WAN_RANGES="${IPTV_WAN_RANGES:-"213.75.0.0/16 217.166.0.0/16"}"
IPTV_WAN_VLAN="${IPTV_WAN_VLAN:-4}"
IPTV_WAN_VLAN_INTERFACE="${IPTV_WAN_VLAN_INTERFACE:-iptv}"
IPTV_WAN_DHCP_OPTIONS="${IPTV_WAN_DHCP_OPTIONS:-"-O staticroutes -V IPTV_RG"}"
IPTV_LAN_INTERFACES="${IPTV_LAN_INTERFACES:-br0}"
IPTV_LAN_RANGES="${IPTV_LAN_RANGES:-""}"

# Setup the network, creating the IPTV VLAN interface if necessary
# and obtaining an IP address for the interface.
_network_setup() {
    local target
    target="$IPTV_WAN_INTERFACE"

    # Make sure we obtain IP address for VLAN interface
    if [ "$IPTV_WAN_VLAN" -ne 0 ]; then
        echo "udm-iptv: Obtaining IP address for VLAN interface..."

        target="$IPTV_WAN_VLAN_INTERFACE"
        tee /etc/network/interfaces <<EOF >/dev/null
auto $IPTV_WAN_VLAN_INTERFACE
iface $IPTV_WAN_VLAN_INTERFACE inet dhcp
    udhcpc_opts $IPTV_WAN_DHCP_OPTIONS
    vlan-id $IPTV_WAN_VLAN
    vlan-raw-device $IPTV_WAN_INTERFACE
EOF

        # Do not update /etc/resolv.conf
        mkdir -p /etc/udhcpc
        tee /etc/udhcpc/udhcpc.conf <<EOF >/dev/null
RESOLV_CONF=no
EOF

        # Start VLAN interface
        ifup -f "$IPTV_WAN_VLAN_INTERFACE"
    fi

    echo "udm-iptv: NATing IPTV network ranges (if necessary)..."

    # NAT the IPTV ranges
    for range in $IPTV_WAN_RANGES; do
        iptables -C POSTROUTING -t nat -d "$range" -j MASQUERADE -o "$target" || iptables -A POSTROUTING -t nat -d "$range" -j MASQUERADE -o "$target"
    done
}

# Build the configuration needed by IGMP Proxy
_igmpproxy_build_config() {
    if [ -z "$IPTV_IGMPPROXY_DISABLE_QUICKLEAVE" ]; then
        echo "quickleave"
    fi

    local target
    if [ "$IPTV_WAN_VLAN" -ne 0 ]; then
        target="$IPTV_WAN_VLAN_INTERFACE"
    else
        target="$IPTV_WAN_INTERFACE"
    fi

    echo "phyint $target upstream  ratelimit 0  threshold 1"
    for range in $IPTV_LAN_RANGES $IPTV_WAN_RANGES; do
        echo "  altnet $range"
    done

    # Configure the igmpproxy interfaces
    for path in /sys/class/net/*; do
        local interface
        interface=$(basename "$path")
        if echo "$IPTV_LAN_INTERFACES" | grep -w -q "$interface"; then
            echo "phyint $interface downstream  ratelimit 0  threshold 1"
        elif [ "$interface" != "lo" ] && [ "$interface" != "$target" ]; then
            echo "phyint $interface disabled"
        fi
    done
}

# Configure IGMP Proxy to bridge multicast traffic
_igmpproxy_setup() {
    echo "udm-iptv: Setting up igmpproxy.."
    _igmpproxy_build_config >/etc/igmpproxy.conf
}

_network_setup
_igmpproxy_setup

echo "udm-iptv: Starting igmpproxy.."
exec igmpproxy -n "$@" /etc/igmpproxy.conf
