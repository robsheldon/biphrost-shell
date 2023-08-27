# Configure networking inside a container

This must be done before packages are downloaded and installed, otherwise networking is broken and everything falls over.

**Parameters**
* --hostnames: the default hostnames to be added to the container
```bash
hostnames="$(needopt hostnames)"
```

First, disable systemd's takeover of the network stack. systemd's configuration changes frequently and it doesn't provide any benefits for hosting containers. See also https://www.naut.ca/blog/2018/12/12/disabling-systemd-networking/
```bash
systemctl stop systemd-resolved systemd-networkd.socket systemd-networkd networkd-dispatcher systemd-networkd-wait-online >/dev/null
systemctl disable systemd-resolved.service systemd-networkd.socket systemd-networkd networkd-dispatcher systemd-networkd-wait-online >/dev/null
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

Generate a default hosts file for the container. The hosts file will contain the container's hostname, if set.
```bash
cat <<EOF | tee /etc/hosts >/dev/null
# IP4
127.0.0.1          $hostnames
10.0.0.1           lxchost

# IP6
::1                $hostnames ip6-localhost ip6-loopback
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


## TODO

* I'd like to not use Cloudflare DNS by default
* There should probably be some sanity-checking done on the hostnames parameter