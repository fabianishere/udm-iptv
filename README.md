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
    - **UniFi Dream Machine Pro SE**: You need
      [Early Access firmware 2.3.7+](https://community.ui.com/releases/UniFi-OS-Dream-Machine-SE-2-3-7/2cf1632b-bcf6-4b13-a61d-f74f1e51242c)
      for multicast routing support.
    - **UniFi Dream Router**: Multicast routing is supported by the default 
      firmware.
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
On the UniFi Dream Machine (Pro), use `unifi-os shell` to enter UniFi OS from
within UbiOS.
```bash
# Download udm-iptv package
curl -O -L https://github.com/fabianishere/udm-iptv/releases/download/v2.1.3/udm-iptv_2.1.3_all.deb
# Download a recent igmpproxy version
curl -O -L http://ftp.debian.org/debian/pool/main/i/igmpproxy/igmpproxy_0.3-1_arm64.deb
# Update APT sources and install dialog package for interactive install
apt update && apt install dialog
# Install udm-iptv and igmpproxy
apt install ./igmpproxy_0.3-1_arm64.deb ./udm-iptv_2.1.3_all.deb
```

It may be possible that `apt` reports a warning after installation (like shown below),
but this has no effect on the installation process, so you can simply ignore it.
> N: Download is performed unsandboxed as root as file '/root/igmpproxy_0.3-1_arm64.deb' couldn't be accessed by user '_apt'. - pkgAcquire::Run (13: Permission denied)

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
|   Vivo SP |   BR    | Yes                                                                                                                 |
|   Telenor |   NO    | Yes                                                                                                                 |
|    PostTV |   LU    | [Manual configuration necessary](https://github.com/fabianishere/udm-iptv/discussions/86#discussioncomment-2345968) |

If your ISP is not supported, you may select the _Custom_ profile, which allows
you manually configure the package to your needs. 
We appreciate if you share the configuration so others can also benefit.
See the [profiles](profiles/) directory for examples of existing configuration
profiles.

The package installs a service that is started during the
boot process of your UniFi device and that will set up the applications
necessary to route IPTV traffic. After installation, the service is automatically
started.

If you experience any issues while setting up the service, please visit the
[Troubleshooting](#troubleshooting-and-known-issues) section.

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
mv /etc/udm-iptv /mnt/persistent
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
Upgrading the installation of udm-iptv is achieved by downloading a new version
of the package and installing it via `apt`. The service should automatically
restart after upgrading.

```bash
curl -O -L https://github.com/fabianishere/udm-iptv/releases/download/v2.1.3/udm-iptv_2.1.3_all.deb
apt install ./udm-iptv_2.1.3_all.deb 
```

### Removal
To fully remove an `udm-iptv` installation from your UniFi device, run the follow command:
```bash
apt remove dialog igmpproxy udm-iptv
```
In order to remove all configuration files as well, run the following command:
```bash
apt purge dialog igmpproxy udm-iptv
```

## Troubleshooting and Known Issues

Below is a non-exhaustive list of issues that might occur while getting IPTV to
run on your UniFi device, as well as troubleshooting steps. Please check these
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

Use the following steps to debug `igmpproxy` if it is behaving strangely. 
Make sure you are running inside UniFi OS.

1. **Enabling debug logs**  
   You can enable `igmpproxy` to report debug messages by setting `IPTV_IGMPPROXY_DEBUG`
   to `true` in the configuration at `/etc/udm-iptv.conf` (within UniFi OS).
   Then, restart the service as follows:
   ```bash
   systemctl restart udm-iptv
   ```
2. **Viewing debug logs**  
   You may now view the debug logs of `igmpproxy` as follows:
   ```bash
   journalctl -u udm-iptv
   ```

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
