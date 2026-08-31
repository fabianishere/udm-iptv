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

```text
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

## Prerequisites

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
4. Set **IPv4 Connection** to *PPPoE*.
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

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/fabianishere/udm-iptv/master/install.sh)"
```

This script will install the `udm-iptv` package onto your device.
The installation process supports various pre-defined configuration profiles for
popular IPTV providers. Below is a list of supported IPTV providers:

|  Provider | Country | Supported                                                                                                           |
| --------: | :-----: | ------------------------------------------------------------------------------------------------------------------- |
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

If your ISP is not supported, you may select the *Custom* profile, which allows
you manually configure the package to your needs.
We appreciate if you share the configuration so others can also benefit.
See the [profiles](profiles) directory for examples of existing configuration
profiles.

<details>
<summary><h4>Installing a different build</h4></summary>

The installer reads the following environment variables:

| Variable                 | Description                                                                            |
| ------------------------ | -------------------------------------------------------------------------------------- |
| UDM_IPTV_VERSION         | Release to install (default `3.0.6`)                                                   |
| UDM_IPTV_REPOSITORY      | Repository to install from (default `fabianishere/udm-iptv`)                           |
| UDM_IPTV_PACKAGE         | Package to install, as a URL or a path on the device                                   |
| UDM_IPTV_STATE_DIR       | Directory to save the answers, configuration and package in (default `/data/udm-iptv`) |
| UDM_IPTV_PR              | Pull request whose build to install, as a number or `owner/repo#number`                |
| UDM_IPTV_RUN             | Workflow run whose build to install, or `latest` for the newest successful one         |
| UDM_IPTV_TOKEN           | Token with `actions:read`, required for `UDM_IPTV_PR` and `UDM_IPTV_RUN`               |
| UDM_IPTV_TIMEOUT_SECONDS | Seconds to wait for a workflow run to finish (default `900`)                           |

Artifacts are only downloadable with a token, including on public
repositories. Releases are not, so `UDM_IPTV_VERSION` and `UDM_IPTV_REPOSITORY` need none.

Copy a token to the device, keeping it out of the command line:

```sh
gh auth token | ssh unifi 'cat > /tmp/.ghtok && chmod 600 /tmp/.ghtok'
```

Install the build of a pull request, waiting for the workflow if it is still
running:

```sh
ssh unifi 'UDM_IPTV_PR="fabianishere/udm-iptv#123" UDM_IPTV_TOKEN=$(cat /tmp/.ghtok) \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/fabianishere/udm-iptv/master/install.sh)"'
```

Remove the token when you are done:

```sh
ssh unifi 'rm -f /tmp/.ghtok'
```

</details>

The package installs a service that is started during the
boot process of your UniFi device and that will set up the applications
necessary to route IPTV traffic. After installation, the service is automatically
started.

Your configuration is saved to `/data` so that it survives a firmware update.
A firmware update removes the package itself, and the installation reinstalls
itself on the next boot. See
[Installation across Firmware Updates](#installation-across-firmware-updates)
and fabianishere/udm-iptv#120.

If you experience any issues while setting up the service, please visit the
[Troubleshooting](#troubleshooting) section.

### Installation across Firmware Updates

A firmware update replaces the read-only layer of the root overlay and discards
the writable layer below `/usr`, which removes `udm-iptv` and its service unit.
`/etc` and `/data` survive. Your answers and your configuration are copied to
`/data/udm-iptv` after every successful configuration, and the installer leaves
a copy of the package there as well.

`udm-iptv-restore.service` is installed in `/etc/systemd/system` and survives as
well. On the first boot after an update it finds the daemon gone, waits for
UniFi OS to finish reinstalling its own packages, and installs the saved copy,
which needs no network access. When there is no saved copy it falls back to
downloading the installer. Nothing needs to be enabled and nothing needs to be
run afterwards.

The same restore runs on demand and does nothing while the service is running,
so it is also safe to schedule from another always-on host:

```sh
ssh unifi /data/udm-iptv/udm-iptv-restore
```

`udm-iptv restore` is the same thing for as long as the package is installed,
and `udm-iptv persist` refreshes the saved copy, which is only useful if you
edit `/etc/udm-iptv.conf` by hand instead of using `udm-iptv configure`.

The restore reads the following environment variables:

| Variable                 | Description                                                                               |
| ------------------------ | ----------------------------------------------------------------------------------------- |
| UDM_IPTV_STATE_DIR       | Directory holding the saved answers, configuration and package (default `/data/udm-iptv`) |
| UDM_IPTV_REPOSITORY      | Repository to fall back to when no package was saved (default `fabianishere/udm-iptv`)    |
| UDM_IPTV_BRANCH          | Branch or commit to take that installer from (default `HEAD`)                             |
| UDM_IPTV_LOCK_TIMEOUT    | Seconds to wait for the package manager to free the dpkg lock (default `1800`)            |
| UDM_IPTV_SYSTEMD_TIMEOUT | Seconds to retry service activation while systemd reloads (default `60`)                  |

`udm-iptv-restore.service` runs `/data/udm-iptv/udm-iptv-restore` by its literal
path, so a different `UDM_IPTV_STATE_DIR` needs the unit adjusted to match.

### Configuration

You can modify the configuration of the service interactively as follows:

```sh
udm-iptv configure
```

See below for a reference of the available options to configure:

| Option                            | Description                                                                                                                                                      |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| IPTV_WAN_INTERFACE                | Interface on which IPTV traffic enters the router                                                                                                                |
| IPTV_WAN_RANGES                   | IP ranges from which the IPTV traffic originates (separated by spaces)                                                                                           |
| IPTV_WAN_VLAN                     | ID of VLAN which carries IPTV traffic (use 0 if no VLAN is used)                                                                                                 |
| IPTV_WAN_DHCP                     | Boolean to indicate whether DHCP is enabled on the IPTV WAN (VLAN) interface                                                                                     |
| IPTV_WAN_DHCP_OPTIONS             | [DHCP options](https://busybox.net/downloads/BusyBox.html#udhcpc) to send when requesting an IP address                                                          |
| IPTV_WAN_STATIC_IP                | Static IP address to assign to the IPTV WAN (VLAN) interface (if DHCP is disabled)                                                                               |
| IPTV_WAN_MAC                      | Custom MAC address to assign to the IPTV WAN VLAN interface                                                                                                      |
| IPTV_LAN_INTERFACES               | Interfaces on which IPTV should be made available                                                                                                                |
| IPTV_IGMPPROXY_DEBUG              | Enable debugging for igmpproxy                                                                                                                                   |
| IPTV_IGMPPROXY_DISABLE_QUICKLEAVE | Boolean to disables the quickleave feature for the IGMP Proxy. Set this to true if you have more than one IPTV decoder. Supported by both improxy and igmpproxy. |

The configuration is written to `/etc/udm-iptv.conf` (within UniFi OS).

### Upgrading

Use the following command to upgrade `udm-iptv`:

```sh
udm-iptv upgrade
```

By default this resolves and installs the latest published release. The command
also accepts an explicit release, package, pull request or workflow run:

```sh
udm-iptv upgrade --version 3.0.6
udm-iptv upgrade --package /data/udm-iptv/udm-iptv.deb
udm-iptv upgrade --pr fabianishere/udm-iptv#123 --token-file /tmp/.ghtok
udm-iptv upgrade --run latest --token-file /tmp/.ghtok
```

An upgrade stops before downloading when the selected release is already
installed. Use `udm-iptv upgrade --force` to download and reinstall it anyway.

Run `udm-iptv upgrade --help` for the complete option list. Firmware restoration
always uses the saved package and never upgrades automatically; this keeps a
firmware update separate from a package update.

If that command does not exist, please re-run the installation script.

### Removal

To fully remove an `udm-iptv` installation from your UniFi device, run the follow command:

```sh
udm-iptv uninstall
```

Or to remove the package but keep the configuration and answers, run:

```sh
udm-iptv uninstall --keep-data
```

## Troubleshooting

Below is a non-exhaustive list of issues that might occur while getting IPTV to
run on your UniFi device, as well as troubleshooting steps. Please check these
instructions before opening a discussion.

1. **Check if your IPTV receiver is on the right VLAN**\
   Your IPTV receiver might not be VLAN to which the IPTV traffic is forwarded.
2. **Check if IPTV traffic is forwarded to the right VLAN**\
   Make sure that you have configured `IPTV_LAN_INTERFACES` correctly to forward
   to right interfaces (e.g., `br4` for VLAN 4).
3. **If you have more than one IPTV decoder, disable the quickleave feature**
   Quickleave is enabled in the default configuration for improxy (the default IGMP proxy) and igmpproxy.
   If you have multiple IPTV decoders, quickleave will stop a stream for all decoders when just one decoder changes to a different stream.
4. **Check if your kernel supports multicast routing**\
   If `MRT_INIT failed; Errno(92): Protocol not available` appears in
   diagnostics, your kernel does not support multicast routing.
5. **Check if your issue has been reported already**\
   Use the GitHub search functionality to check if your issue has already been
   reported before.

### Getting Help or Reporting an Issue

If your issues persist, you may seek help on our [Discussions](https://github.com/fabianishere/udm-iptv/discussions) page.
Please keep [GitHub Issues](https://github.com/fabianishere/udm-iptv/issues)
only for bugs or feature requests related to the project (no configuration-related issues).

When opening a discussion or reporting an issue, **please share the name of your
ISP as well as the diagnostics reported by our diagnostic tool**:

```sh
udm-iptv diagnose
```

## Contributing

Questions, suggestions and contributions are welcome and appreciated!
You can contribute in various meaningful ways:

- Report a bug through [GitHub issues](https://github.com/fabianishere/udm-iptv/issues).
- Contribute improvements to the documentation (e.g., configuration for other ISPs).
- Help answer questions on our [Discussions](https://github.com/fabianishere/udm-iptv/discussions) page.

## License

The code is released under the GPLv2 license. See [COPYING.txt](/COPYING.txt).

<!-- markdownlint-disable-file line-length no-inline-html -->
