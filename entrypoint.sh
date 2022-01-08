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
    if [ "$IPTV_WAN_VLAN" -gt 0 ]; then
        echo "Obtaining IP address for VLAN interface"

        target="$IPTV_WAN_VLAN_INTERFACE"

        # Create VLAN interface (if it does not exist)
        if [ -e /sys/class/net/"$IPTV_WAN_VLAN_INTERFACE" ]; then
            echo "Device $IPTV_WAN_VLAN_INTERFACE already exists"
        elif ! ip link show "$IPTV_WAN_INTERFACE" >/dev/null; then
            echo "Device $IPTV_WAN_INTERFACE for $IPTV_WAN_VLAN_INTERFACE does not exist"
            exit 1
        else
            ip link add link "$IPTV_WAN_INTERFACE" name "$IPTV_WAN_VLAN_INTERFACE" type vlan id "$IPTV_WAN_VLAN"
        fi

        # Bring VLAN interface up
        ip link set dev "$IPTV_WAN_VLAN_INTERFACE" up

         # Do not update /etc/resolv.conf
        export RESOLV_CONF=no

        # Obtain IP address for VLAN interface
        udhcpc -b -R -p /var/run/udhcpc."$IPTV_WAN_VLAN_INTERFACE".pid -i "$IPTV_WAN_VLAN_INTERFACE" $IPTV_WAN_DHCP_OPTIONS
    fi

    echo "NATing IPTV network ranges (if necessary)"

    # NAT the IPTV ranges
    for range in $IPTV_WAN_RANGES; do
        # Only add the NAT rule if it does not yet exist
        if ! iptables -C POSTROUTING -t nat -d "$range" -j MASQUERADE -o "$target" >/dev/null 2>&1; then
            iptables -A POSTROUTING -t nat -d "$range" -j MASQUERADE -o "$target"
        fi
    done
}

# Build the configuration needed by IGMP Proxy
_igmpproxy_build_config() {
    echo "# igmpproxy configuration for udm-iptv"
    if [ -z "$IPTV_IGMPPROXY_DISABLE_QUICKLEAVE" ]; then
        echo "quickleave"
    fi

    local target
    if [ "$IPTV_WAN_VLAN" -gt 0 ]; then
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
    echo "Setting up igmpproxy"
    _igmpproxy_build_config >/var/run/igmpproxy.iptv.conf
}

_network_setup
_igmpproxy_setup

echo "Starting igmpproxy"
exec igmpproxy -n "$@" /var/run/igmpproxy.iptv.conf
