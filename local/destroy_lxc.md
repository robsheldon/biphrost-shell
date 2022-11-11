# Destroy an LXC container

**Warning:** This cannot be undone.

**Parameters**
* --confirm: "y" to auto-confirm this (required for non-interactive sessions)
```bash
confirmation="$(loadopt "confirm")"
```

Get the name of the container to be deleted. Should be passed as the next argument directly after the name of the script.
```bash
shift; shift
if [ "$#" -lt 1 ]; then
    fail "No container name given"
	exit 1
fi
lxcname="$1"
shift
```

**Make sure this is running an on lxchost**
```bash
if ! command -v lxc-destroy >/dev/null; then
    fail "lxc-destroy is not available; is this an LXC host?"
	exit 1
fi
```

**Make sure the container name matches only one container**
This script will continue even if a matching container isn't found so that aborted container deployments can be cleaned up.
```bash
matches="$(sudo lxc-ls 2>/dev/null | grep -cP "\\b$lxcname\\b")"
if [ "$matches" -gt 1 ]; then
	fail "$lxcname is ambiguous and matches multiple containers"
	exit 1
fi
```

**Ask the user for confirmation**
```bash
if [ "$confirmation" != "y" ]; then
	if ! ask "Really destroy $lxcname?"; then
		fail "User canceled"
		exit 1
	fi
fi

echo "Deleting $lxcname!"
```

**Stop the container**
```bash
if [ "$(biphrost -b status "$lxcname")" = "RUNNING" ]; then
    sudo lxc-stop "$lxcname"
fi
```

**Delete the container's knockd entry**
These lines delete a matching knockd entry for this container, and then delete a trailing blank line from the config file if one exists. sed doesn't seem to want to do this in a single operation without the sed command getting ugly.
```bash
sudo sed -i -e "/^\\[$lxcname\\]\$/,+5d;" /etc/knockd.conf
sudo sed -i -e '${/^$/d;}' /etc/knockd.conf
sudo service knockd restart
```

**Delete the container's hosts file entry**
```bash
sudo sed -i -e "/^[0-9\\.]\\+\\s\\+$lxcname\$/d" /etc/hosts
```

**Disable the lxc user's service file**
```bash
if id -u "$lxcname" >/dev/null; then
    sudo -u "$lxcname" XDG_RUNTIME_DIR="/run/user/$(sudo -u "$lxcname" sh -c 'id -u')" sh -c "systemctl --user disable $lxcname-autostart"
fi
sudo loginctl disable-linger "$lxcname" 2>/dev/null
```

**Destroy the container**
```bash
if [ "$(biphrost -b status "$lxcname")" != "NOTFOUND" ]; then
    sudo lxc-destroy "$lxcname"
fi
```

**Delete the user and their home directory**
```bash
if id -u "$lxcname" >/dev/null; then
    sudo userdel -r "$lxcname"
fi
```

**Make sure related directories are deleted**
This is risky. `sudo find /dir -maxdepth 1 -mindepth 1 -type d -iname "$lxcname" -delete` would be nice but `find` won't delete non-empty directories.
```bash
if [ -n "$lxcname" ] && [[ $lxcname =~ lxc[0-9]{4} ]]; then
    if [ -d "/home/$lxcname" ]; then
        sudo find "/home/$lxcname" -delete
    fi
    if [ -d "/srv/lxc/$lxcname" ]; then
        sudo find "/srv/lxc/$lxcname" -delete
    fi
fi
```