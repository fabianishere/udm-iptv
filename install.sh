#!/bin/sh
# Installation script for the udm-iptv service
#
# Copyright (C) 2022 Fabian Mastenbroek.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

set -e

if command -v unifi-os > /dev/null 2>&1; then
    echo "error: You need to be in UniFi OS to run the installer."
    echo "Please run the following command to enter UniFi OS:"
    echo
    printf "\t unifi-os shell\n"
    exit 1
fi

UDM_IPTV_VERSION=3.0.0
IGMPPROXY_VERSION=0.3-1

dest=$(mktemp -d)

echo "Downloading packages..."

# Download udm-iptv package
curl -sS -o "$dest/udm-iptv.deb" -L "https://github.com/fabianishere/udm-iptv/releases/download/v$UDM_IPTV_VERSION/udm-iptv_${UDM_IPTV_VERSION}_all.deb"

# Download a recent igmpproxy version
curl -sS -o "$dest/igmpproxy.deb" -L "http://ftp.debian.org/debian/pool/main/i/igmpproxy/igmpproxy_${IGMPPROXY_VERSION}_arm64.deb"

# Fix permissions on the packages
chown _apt:root "$dest/udm-iptv.deb" "$dest/igmpproxy.deb"

echo "Installing packages..."

# Update APT sources
apt-get update -q

# Install dialog package for interactive install
apt-get install -q -y dialog

# Install udm-iptv and igmpproxy
apt-get install -q -y "$dest/igmpproxy.deb" "$dest/udm-iptv.deb"

echo "Installation successful... You can find your configuration at /etc/udm-iptv.conf."
echo
echo "Use the following command to reconfigure the script:"
echo
printf "\t udm-iptv reconfigure\n"
