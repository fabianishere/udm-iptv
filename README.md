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
   in order to support IPTV. Please upgrade to the latest firmware.
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

### Installation across Firmware Updates

To ensure your installation remains working across firmware updates, you may
need to perform some manual steps which are described below.

**Please remember to make a backup of your configuration before a 
firmware update**. Changes in Ubiquiti's future firmware (flashing process)
might potentially cause your configuration to be lost.

#### UniFi Dream Machine (Pro)
Custom packages on the UniFi Dream Machine (Pro) are re-installed after 
firmware upgrades, but custom configuration is lost. 

You may move the configuration file to a persistent location and copy back
the configuration after the firmware upgrade.

```bash
# Copy to persistent storage
cp /etc/udm-iptv.conf /mnt/persistent/udm-iptv.conf
# Copy from persistent storage
cp /mnt/persistent/udm-iptv.conf /etc/udm-iptv.conf
```

#### UniFi Dream Machine SE and UniFi Dream Router
It is currently not possible to persist the installation across firmware updates
(see [#120](https://github.com/fabianishere/udm-iptv/issues/120)). Your configuration should remain, so only re-installation is necessary.

### Configuration
You can modify the configuration of the service interactively as follows:
```bash
udm-iptv configure
```
See below for a reference of the available options to configure:

| Option                | Description                                                                                             |
|-----------------------|---------------------------------------------------------------------------------------------------------|
| IPTV_WAN_INTERFACE    | Interface on which IPTV traffic enters the router                                                       |
| IPTV_WAN_RANGES       | IP ranges from which the IPTV traffic originates (separated by spaces)                                  |
| IPTV_WAN_VLAN         | ID of VLAN which carries IPTV traffic (use 0 if no VLAN is used)                                        |
| IPTV_WAN_DHCP         | Boolean to indicate whether DHCP is enabled on the IPTV WAN (VLAN) interface                            |
| IPTV_WAN_DHCP_OPTIONS | [DHCP options](https://busybox.net/downloads/BusyBox.html#udhcpc) to send when requesting an IP address |
| IPTV_WAN_STATIC_IP    | Static IP address to assign to the IPTV WAN (VLAN) interface (if DHCP is disabled)                      |
| IPTV_WAN_MAC          | Custom MAC address to assign to the IPTV WAN VLAN interface                                             |
| IPTV_LAN_INTERFACES   | Interfaces on which IPTV should be made available                                                       |
| IPTV_IGMPPROXY_DEBUG  | Enable debugging for igmpproxy                                                                          |

The configuration is written to `/etc/udm-iptv.conf` (within UniFi OS).

### Upgrading
Use the following command to upgrade `udm-iptv`:
```bash
udm-iptv upgrade
```
If that command does not exist, please re-run the installation script.

### Removal
To fully remove an `udm-iptv` installation from your UniFi device, run the follow command:
```bash
udm-iptv uninstall
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
3. **Check if your kernel supports multicast routing**  
   If `MRT_INIT failed; Errno(92): Protocol not available` appears in 
   diagnostics, your kernel does not support multicast routing.
4. **Check if your issue has been reported already**  
   Use the GitHub search functionality to check if your issue has already been
   reported before.

### Getting Help or Reporting an Issue
If your issues persist, you may seek help on our [Discussions](https://github.com/fabianishere/udm-iptv/discussions) page.
Please keep [GitHub Issues](https://github.com/fabianishere/udm-iptv/issues)
only for bugs or feature requests related to the project (no configuration-related issues).

When opening a discussion or reporting an issue, **please share the name of your
ISP as well as the diagnostics reported by our diagnostic tool**:
```bash
udm-iptv diagnose
```

## Contributing
Questions, suggestions and contributions are welcome and appreciated!
You can contribute in various meaningful ways:

* Report a bug through [GitHub issues](https://github.com/fabianishere/udm-iptv/issues).
* Contribute improvements to the documentation (e.g., configuration for other ISPs).
* Help answer questions on our [Discussions](https://github.com/fabianishere/udm-iptv/discussions) page.

## License
The code is released under the GPLv2 license. See [COPYING.txt](/COPYING.txt).
