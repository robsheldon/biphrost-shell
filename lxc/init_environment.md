# Initialize a container

This must be run *after* the network is configured and up (because `apt upgrade` and `apt install ...` require it).

**Parameters**
* --label: the label (name) for the container to be inited
```bash
label="$(needopt label -m '^lxc[0-9]{4}$')"
```

**Update packages, install some common requirements**
```bash
if apt purge -y joe </dev/null; then
    echo 'Removed joe'
fi
if apt-get update </dev/null; then
    echo 'Retrieved package updates'
fi
if apt-get upgrade -y </dev/null; then
    echo 'Installed package updates'
fi
if apt install -y patch sudo rsync openssh-server git </dev/null; then
    echo 'Installed patch, sudo, rsync, sshd, and git'
fi
```

**Configure the hostname**
```bash
echo "$label" > /etc/hostname
hostname -F /etc/hostname
```

**Configure sshd**
```bash
# shellcheck disable=SC2086
sed -i 's/^#*\s*PermitRootLogin.*$/PermitRootLogin no\nAllowGroups '$label'/g' /etc/ssh/sshd_config
sed -i 's/^#*\s*X11Forwarding.*$/X11Forwarding no/g' /etc/ssh/sshd_config
sed -i 's/^#*\s*PasswordAuthentication.*$/PasswordAuthentication no/g' /etc/ssh/sshd_config
if ! sshd -t; then
    echo "Error updating sshd configuration in $label"
    exit 1
fi
service ssh restart
```

**Set the timezone and locale**
```bash
timedatectl set-timezone America/Los_Angeles
localedef -i en_US -f UTF-8 en_US.UTF-8
```

**Set some defaults for the root account**
```bash
update-alternatives --set editor /usr/bin/vim.basic
```

**Create the LXC user inside the container**
This is done so that applications installed inside the container have a safe, valid, unprivileged, default user account. When a user connects to their container over ssh, they will be dropped in to this user account.
```bash
adduser --quiet --disabled-password --gecos '' "$label" >/dev/null
mkdir -p "/home/$label/.ssh"
touch "/home/$label/.ssh/authorized_keys"
chown -R "$label":"$label" "/home/$label/.ssh"
chmod 0750 "/home/$label/.ssh"
chmod 0640 "/home/$label/.ssh/authorized_keys"
```
