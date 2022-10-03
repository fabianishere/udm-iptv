# IPTV on UniFi OS

This document describes how to set up IPTV on UniFi routing devices based on 
UniFi OS, such as the UniFi Dream Machine (UDM) or the UniFi Dream Router (UDR).
These instructions have been tested with the IPTV network from KPN
(ISP in the Netherlands).
However, the general approach should be applicable for other ISPs as well.

For getting IPTV to work on the legacy UniFi Security Gateway, please refer to
the [following guide](https://github.com/basmeerman/unifi-usg-kpn).

## Contents

1. [Global Design](#global-design)
2. [Prerequisites](#prerequisites)
3. [Setting up Internet Connection](#setting-up-internet-connection)
4. [Configuring Internal LAN](#configuring-internal-lan)
5. [Configuring Helper Tool](#configuring-helper-tool)
6. [Troubleshooting and Known Issues](#troubleshooting)

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
      +--------+
      | Router |  - Ubiquiti UniFi device
      +--------+
          |
         LAN
          |
      +--------+
      | Switch |  - Ubiquiti UniFi Switch (Optional)
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

1. The kernel on your UniFi device must support multicast routing
   in order to support IPTV:
    - **UniFi Dream Machine (Pro)**: Multicast routing is supported natively in the stock kernel since
   [firmware version 1.11](https://community.ui.com/releases/UniFi-OS-Dream-Machines-1-11-0/eef95803-6976-499b-9169-bf6dfbbcc209). 
   If you for some reason cannot use firmware v1.11+, see [udm-kernel](https://github.com/fabianishere/udm-kernel)
   for a kernel that supports multicast routing for older firmware versions of the UDM/P.
    - **UniFi Dream Machine SE**: You need firmware version 2.3.7+ for multicast routing support.
    - **UniFi Dream Router**: Multicast routing is supported by the default firmware.
2. The switches in-between the IPTV decoder and the UniFi device should have IGMP
   snooping enabled. They do not need to be from Ubiquiti necessarily.
3. The FTTP NTU (or any other type of modem) of your ISP must be connected to
   one of the WAN ports of your UniFi device.

## Setting up Internet Connection

The first step is to set up your internet connection to your ISP with the UniFi
device acting as modem, instead of some intermediate device. These steps might
differ per ISP, so please check the requirements for your ISP.

Below, we describe the steps for KPN. Feel free to update this document with the
steps necessary for your provider.

### KPN
If you are a customer of KPN, you can set up the WAN connection as follows:

1. In your UniFi Dashboard, go to **Settings > Internet**.
2. Select the WAN port that is connected to the FTTP NTU.
3. Enable **VLAN ID** and set it to 6 for KPN.
4. Set **IPv4 Connection** to _PPPoE_.
5. For KPN, **Username** should be set to `internet`.
6. For KPN, **Password** should be set to `internet`.

## Configuring Internal LAN

To operate correctly, the IPTV decoders on the internal LAN possibly require
additional DHCP options. You can add these DHCP options as follows:

1. In your UniFi Dashboard, go to **Settings > Networks**.
2. Select the LAN network on which IPTV will be used.
   We recommend creating a separate LAN network for IPTV traffic if possible in
   order to reduce interference of other devices on the network.
3. Enable **Advanced Configuration > IGMP Snooping**, so IPTV traffic is only
   sent to devices that should receive it.
4. Go to **DHCP > Custom DHCP Option** and add the following options:

   | Name       | Code | Type       | Value               |
   |------------|:----:|------------|---------------------|
   | IPTV-Class |  60  | Text       | IPTV_RG             |


## Configuring Helper Tool

Next, we will use the udm-iptv package to get IPTV working on your LAN.
This package uses [igmpproxy](https://github.com/pali/igmpproxy) to route 
multicast IPTV traffic between WAN and LAN.

### Installation
SSH into your machine and execute the commands below in UniFi OS (not in UbiOS).
```bash
sh -c "$(curl https://raw.githubusercontent.com/fabianishere/udm-iptv/master/install.sh -sSf)"
```

This script will install the `udm-iptv` package onto your device.
The installation process supports various pre-defined configuration profiles for
popular IPTV providers. Below is a list of supported IPTV providers: 

|  Provider | Country | Supported                                                                                                           |
|----------:|:-------:|---------------------------------------------------------------------------------------------------------------------|
|       KPN |   NL    | Yes                                                                                                                 |
|    XS4ALL |   NL    | Yes                                                                                                                 |
|     Tweak |   NL    | Yes                                                                                                                 |
|    Solcon |   NL    | Yes                                                                                                                 |
|   Telekom |   DE    | [Manual configuration necessary](https://github.com/fabianishere/udm-iptv/discussions/8)                            |
| MagentaTV |   DE    | [Manual configuration necessary](https://github.com/fabianishere/udm-iptv/issues/2#issuecomment-1007413230)         |
|  Swisscom |   CH    | Yes                                                                                                                 |
|     Init7 |   CH    | Yes                                                                                                                 |
|       MEO |   PT    | Yes                                                                                                                 |
|        BT |   GB    | Yes                                                                                                                 |
|   Vivo SP |   BR    | Yes - Tested with GPON TP-Link TX-6610                                                                              |
|  Vivo GVT |   BR    | Yes - [Manual configuration necessary](https://github.com/fabianishere/udm-iptv/issues/167#issuecomment-1244797462) |
|   Telenor |   NO    | Yes                                                                                                                 |
|    PostTV |   LU    | [Manual configuration necessary](https://github.com/fabianishere/udm-iptv/discussions/86#discussioncomment-2345968) |

If your ISP is not supported, you may select the _Custom_ profile, which allows
you manually configure the package to your needs. 
We appreciate if you share the configuration so others can also benefit.
See the [profiles](profiles) directory for examples of existing configuration
profiles.

The package installs a service that is started during the
boot process of your UniFi device and that will set up the applications
necessary to route IPTV traffic. After installation, the service is automatically
started.

If you experience any issues while setting up the service, please visit the
[Troubleshooting](#troubleshooting) section.

### Ensuring Installation across Firmware Updates

To ensure your installation remains persistent across firmware updates, you may
need to perform some manual steps which are described below.

Even so, **please remember to make a backup of your configuration before a 
firmware update**. Changes in Ubiquiti's future firmware (flashing process)
might potentially cause your configuration to be lost.

#### UniFi Dream Machine (Pro)
Custom packages on the UniFi Dream Machine (Pro) are re-installed after a firmware
updates, but custom configuration is lost. To ensure your configuration remains
persistent, move the configuration file to a persistent location and create a symlink:

```bash
mv /etc/udm-iptv.conf /mnt/persistent
ln -sf /mnt/persistent/udm-iptv.conf /etc/udm-iptv.conf
```
Make sure to re-create the symlink after a firmware upgrade.

#### UniFi Dream Machine SE and UniFi Dream Router
It is currently not possible to persist the installation across firmware updates
(see #120). Your configuration should remain, so only re-installation is necessary.

### Configuration
You can modify the configuration of the service interactively using `dpkg-reconfigure -p medium udm-iptv`.
See below for a reference of the available options to configure:

| Environmental Variable | Description                                                                                             | Default                            |
|------------------------|---------------------------------------------------------------------------------------------------------|------------------------------------|
| IPTV_WAN_INTERFACE     | Interface on which IPTV traffic enters the router                                                       | eth8 (on UDM Pro) or eth4 (on UDM) |
| IPTV_WAN_RANGES        | IP ranges from which the IPTV traffic originates (separated by spaces)                                  | 213.75.0.0/16 217.166.0.0/16       |
| IPTV_WAN_VLAN          | ID of VLAN which carries IPTV traffic (use 0 if no VLAN is used)                                        | 4                                  |
| IPTV_WAN_DHCP          | Boolean to indicate whether DHCP is enabled on the IPTV WAN (VLAN) interface                            | true                               |
| IPTV_WAN_DHCP_OPTIONS  | [DHCP options](https://busybox.net/downloads/BusyBox.html#udhcpc) to send when requesting an IP address | -O staticroutes -V IPTV_RG         |
| IPTV_WAN_STATIC_IP     | Static IP address to assign to the IPTV WAN (VLAN) interface (if DHCP is disabled)                      |                                    |
| IPTV_WAN_MAC           | Custom MAC address to assign to the IPTV WAN VLAN interface                                             |                                    |
| IPTV_LAN_INTERFACES    | Interfaces on which IPTV should be made available                                                       | br0                                |
| IPTV_IGMPPROXY_DEBUG   | Enable debugging for igmpproxy                                                                          | false                              |

The configuration is written to `/etc/udm-iptv.conf` (within UniFi OS).

### Upgrading
To upgrade `udm-iptv`, please re-run the installation script.

### Removal
To fully remove an `udm-iptv` installation from your UniFi device, run the follow command:
```bash
apt remove dialog igmpproxy udm-iptv
```
In order to remove all configuration files as well, run the following command:
```bash
apt purge dialog igmpproxy udm-iptv
```

## Troubleshooting

Below is a non-exhaustive list of issues that might occur while getting IPTV to
run on your UniFi device, as well as troubleshooting steps. Please check these
instructions before opening a discussion.

1. **Check if your IPTV receiver is on the right VLAN**  
   Your IPTV receiver might not be VLAN to which the IPTV traffic is forwarded.
2. **Check if IPTV traffic is forwarded to the right VLAN**  
   Make sure that you have configured `IPTV_LAN_INTERFACES` correctly to forward
   to right interfaces (e.g., `br4` for VLAN 4).
3. **Check if your issue has been reported already**  
   Use the GitHub search functionality to check if your issue has already been
   reported before.

### Getting Help or Reporting an Issue
If your issues persist, you may seek help on our [Discussions](https://github.com/fabianishere/udm-iptv/discussions) page.
Please keep [GitHub Issues](https://github.com/fabianishere/udm-iptv/issues)
only for bugs or feature requests related to the project (no configuration-related issues).

When opening a discussion or reporting an issue, **please share the name of your
ISP as well as the diagnostics reported by our diagnostic tool**:
```bash
udm-iptv-diag
```

## Contributing
Questions, suggestions and contributions are welcome and appreciated!
You can contribute in various meaningful ways:

* Report a bug through [GitHub issues](https://github.com/fabianishere/udm-iptv/issues).
* Contribute improvements to the documentation (e.g., configuration for other ISPs).
* Help answer questions on our [Discussions](https://github.com/fabianishere/udm-iptv/discussions) page.

## License
The code is released under the GPLv2 license. See [COPYING.txt](/COPYING.txt).
