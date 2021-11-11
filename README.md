# IPTV on the UniFi Dream Machine

This document describes how to set up IPTV on the UniFi Dream Machine (Pro).
These instructions have been tested with the IPTV network from KPN
(ISP in the Netherlands).
However, the general approach should be applicable for other ISPs as well.

For getting IPTV to work on the UniFi Security Gateway, please refer to the
[following guide](https://github.com/basmeerman/unifi-usg-kpn).

## Contents

1. [Global Design](#global-design)
1. [Prerequisites](#prerequisites)
1. [Setting up Internet Connection](#setting-up-internet-connection)
1. [Configuring Internal LAN](#configuring-internal-lan)
1. [Configuring Helper Tool](#configuring-helper-tool)
1. [Troubleshooting and Known Issues](#troubleshooting-and-known-issues)

## Global Design

```
        Fiber
          |
    +----------+
    | FTTH NTU |
    +----------+
          |
      VLAN4 - IPTV
      VLAN6 - Internet
          |
      +-------+
      | UDM/P |   - Ubiquiti UniFi Dream Machine
      +-------+
          |
         LAN
          |
      +--------+
      | Switch |  - Ubiquiti UniFi Switch
      +--------+
       |  |  |
       |  |  +-----------------------------+
       |  |                                |
       |  +-----------------+              |
       |                    |              |
+--------------+       +---------+      +-----+
| IPTV Decoder |       | WiFi AP |      | ... |
+--------------+       +---------+      +-----+
  - KPN IPTV
  - Netflix
```

# Prerequisites

Make sure you check the following prerequisites before trying the other steps:

1. The kernel on your UniFi Dream Machine (Pro) must support multicast routing
   in order to support IPTV. The stock UDM/P kernel starting from
   [firmware version 1.11](https://community.ui.com/releases/UniFi-OS-Dream-Machines-1-11-0-14/71916646-d8f6-41c0-b145-2fbe2db7c278)
   now support multicast routing natively.
   If you cannot use the latest firmware version, see [udm-kernel](https://github.com/fabianishere/udm-kernel)
   for a kernel that supports multicast routing for older firmware versions of
   the UDM/P.
2. You must
   have [on-boot-script](https://github.com/boostchicken/udm-utilities/tree/master/on-boot-script)
   installed on your UDM/P.
3. The switches in-between the IPTV decoder and the UDM/P must have IGMP
   snooping enabled. They do not need to be from Ubiquiti necessarily.
4. The FTTP NTU (or any other type of modem) of your ISP must be connected to 
   one of the WAN ports on the UDM/P.

## Setting up Internet Connection

The first step is to set up your internet connection to your ISP with the UDM/P
acting as modem, instead of some intermediate device. These steps might differ
per ISP, so please check the requirements for your ISP.

### KPN
If you are a customer of KPN, you can set up the WAN connection as follows:

1. In your UniFi Dashboard, go to **Settings > Internet**.
2. Select the WAN port that is connected to the FTTP NTU.
3. Enable **VLAN ID** and set it to the Internet VLAN of your ISP (VLAN6 for
   KPN).
4. Set **IPv4 Connection** to _PPPoE_.
5. For KPN, **Username** should be set to `xx-xx-xx-xx-xx-xx@internet` where
   the `xx-xx-xx-xx-xx-xx` is replaced by the MAC address of your modem, with
   the semicolons (":") replaced with dashes ("-").
6. For KPN, **Password** should be set to `ppp`.

## Configuring Internal LAN

To operate correctly, the IPTV decoders on the internal LAN possibly require
additional DHCP options. You can add these DHCP options as follows:

1. In your UniFi Dashboard, go to **Settings > Networks**.
2. Select the LAN network on which IPTV will be used.
   We recommend creating a separate LAN network for IPTV traffic if possible in
   order to reduce interference of other devices on the network.
4. Enable **Advanced > IGMP Snooping**, so IPTV traffic is only sent to
   devices that should receive it.
5. Go to **Advanced > DHCP Option** and add the following options:

   | Name      | Code | Type       | Value          |
   |-----------|:----:|------------|----------------|
   | IPTV      |  60  | Text       | IPTV_RG        |
   | Broadcast |  28  | IP Address | _BROADCAST_ADDRESS_ |

   Replace _BROADCAST_ADDRESS_ with the broadcast address of your LAN network.
   To get this address, you can obtain it by setting all bits outside the subnet
   mask of your IP range, for instance:
   ```
   192.168.X.1/24 => 192.168.X.255
   192.168.0.1/16 => 192.168.255.255
   ```
   See [here](https://en.wikipedia.org/wiki/Broadcast_address) for more
   information.

## Configuring Helper Tool

Next, we will use the [udm-iptv](https://hub.docker.com/r/fabianishere/udm-iptv)
container to get IPTV working on your LAN. This container uses
[igmpproxy](https://github.com/pali/igmpproxy) to route multicast IPTV traffic between WAN and LAN.

### Installation
Before we set up the `udm-iptv` container, make sure you have the
[on-boot-script](https://github.com/boostchicken/udm-utilities/tree/master/on-boot-script)
installed.  SSH into your machine and execute the following command:

```bash
sh -c "$(curl -s https://raw.githubusercontent.com/fabianishere/udm-iptv/master/install.sh)"
```

This script will install a boot script that runs after every boot of your
UniFi Dream Machine and will set up the applications necessary to route
IPTV traffic.
You may also download and inspect the script manually before running it.


Below is a useful list of configuration values for various IPTV providers:

| Provider | WAN VLAN | WAN Ranges | Notes |
| ---------|---------:|------------|-------|
| KPN (NL) | 4 | 213.75.0.0/16 217.166.0.0/16 | |

Feel free to update this list with the configuration of your provider.

### Running
After installation, run the IPTV container as follows:
```bash
/mnt/data/on_boot.d/15-iptv.sh
```

### Updating
You can update the IPTV container as follows:

```bash
podman pull fabianishere/udm-iptv
```

### Configuration
You can modify the configuration of the container after installation in the installed
boot script at `/mnt/data/on_boot.d/15-iptv.sh`. 
See below for a reference of the available options to configure.

| Environmental Variable | Description | Default |
| ------------------------|----------- |---------|
| IPTV_WAN_INTERFACE      | Interface on which IPTV traffic enters the router | eth8 (on UDM Pro) or eth4 (on UDM) |
| IPTV_WAN_RANGES         | IP ranges from which the IPTV traffic originates (separated by spaces) | 213.75.0.0/16 217.166.0.0/16 |
| IPTV_WAN_VLAN           | ID of VLAN which carries IPTV traffic (use 0 if no VLAN is used) | 4 |
| IPTV_WAN_VLAN_INTERFACE | Name of the VLAN interface to be created | iptv |
| IPTV_WAN_DHCP_OPTIONS   | [DHCP options](https://busybox.net/downloads/BusyBox.html#udhcpc) to send when requesting an IP address | -O staticroutes -V IPTV_RG |
| IPTV_LAN_INTERFACES     | Interfaces on which IPTV should be made available | br0 |

## Troubleshooting and Known Issues

Below is a non-exhaustive list of issues that might occur while getting IPTV to
run on the UDM/P, as well as troubleshooting steps. Please check these
instructions before reporting an issue on issue tracker.

### Debugging DHCP

Use the following steps to verify whether the IPTV container is obtaining an
IP address from the IPTV network via DHCP:

1. Verify that the VLAN interface has obtained an IP address:
   ```bash
   $ ip -4 addr show dev iptv
   43: iptv@eth8: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default
      inet XX.XX.XX.XX/22 brd XX.XX.XX.XX scope global iptv
        valid_lft forever preferred_lft forever
   ```
2. Verify that you have obtained the routes from the DHCP server:
   ```bash
   $ ip route list
   ...
   XX.XX.XX.X/21 via XX.XX.XX.X dev iptv
   ```

### Debugging IGMP Proxy

Use the following steps to debug `igmpproxy` if it is behaving strangely:

1. **Enabling debug logs**  
   You can enable `igmpproxy` to report debug messages by adding the following
   flags to the script in `/mnt/data/on_boot.d/15-iptv.sh`:
   ```diff
      podman run --network=host --privileged \
        -e IPTV_WAN_INTERFACE="eth8" \
        -e IPTV_WAN_RANGES="213.75.112.0/21 217.166.0.0/16" \
        -e IPTV_LAN_INTERFACES="br0" \
   -    fabianishere/udm-iptv
   +    fabianishere/udm-iptv -d -v
      ```
   Make sure you run the script afterwards to apply the changes.
2. **Viewing debug logs**  
   You may now view the debug logs of `igmpproxy` as follows:
   ```bash
   podman logs iptv
   ```

## Contributing
Questions, suggestions and contributions are welcome and appreciated!
You can contribute in various meaningful ways:

* Report a bug through [Github issues](https://github.com/fabianishere/udm-iptv/issues).
* Contribute improvements to the documentation (e.g., configuration for other ISPs).
* Help answer questions on our [Discussions](https://github.com/fabianishere/udm-iptv/discussions) page.

## License
The code is released under the GPLv2 license. See [COPYING.txt](/COPYING.txt).
