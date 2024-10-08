# Configure networking inside a container

This must be done before packages are downloaded and installed, otherwise networking is broken and everything falls over.

**Set the timezone and locale**
We do this here because network initialization happens before environment initialization (hard to get package updates before configuring the network), and because we want consistent timestamps in the setup log. This *should* be a fairly safe command to run before starting the log...
```bash
timedatectl set-timezone America/Los_Angeles
localedef -i en_US -f UTF-8 en_US.UTF-8
```

**Start the log**
```bash
echo "$(date +'%T')" "$(date +'%F')" "Configuring network."
```

Disable systemd's takeover of the network stack. systemd's configuration changes frequently and it doesn't provide any benefits for hosting containers. See also https://www.naut.ca/blog/2018/12/12/disabling-systemd-networking/
```bash
systemctl stop systemd-resolved systemd-networkd.socket systemd-networkd networkd-dispatcher systemd-networkd-wait-online >/dev/null 2>&1
systemctl disable systemd-resolved.service systemd-networkd.socket systemd-networkd networkd-dispatcher systemd-networkd-wait-online >/dev/null 2>&1
apt-get -y purge dhcpcd5 isc-dhcp-client isc-dhcp-common >/dev/null
rm -f /etc/resolv.conf
```

Once that's done, the rest of the network configuration should be able to proceed.
```bash
mkdir -p /etc/network/interfaces.d
touch /etc/network/interfaces
cat <<'EOF' | tee /etc/network/interfaces >/dev/null
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

# The loopback network interface
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet manual

source /etc/network/interfaces.d/*
EOF
```

Generate a default hosts file for the container.
```bash
cat <<EOF | tee /etc/hosts >/dev/null
# IP4
127.0.0.1          localhost
10.0.0.1           lxchost

# IP6
::1                ip6-localhost ip6-loopback
ff02::1            ip6-allnodes
ff02::2            ip6-allrouters

EOF
```

Configure the container to use Cloudflare's public DNS.
```bash
echo "nameserver 1.1.1.1" | tee /etc/resolv.conf >/dev/null
chmod 0644 /etc/resolv.conf
```


**NOTE: CONTAINER MUST BE RESTARTED FOR CHANGES TO TAKE EFFECT**
```bash
echo "$(date +'%T') Network configured. Container needs to be restarted."
```


## TODO

* I'd like to not use Cloudflare DNS by default