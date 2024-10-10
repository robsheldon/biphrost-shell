# Configure hostnames inside a container

This command gets invoked by a Biphrost local script, which has already handled hostname validation.

The primary hostname should be the first hostname provided in the argument list.

**TODO**
* Update Apache/etc. config in the container

**Load hostnames from argument list**
```bash
if [ "${*:1:2}" = "set hostnames" ]; then
    shift; shift
else
    fail "Invalid invocation"
fi
if [ $# -lt 1 ]; then
    fail "No hostnames given"
fi
```

**Get the default hostname from the argument list**
This is expected to be the first argument in the list.
```bash
all_hostnames="$*"
default_hostname="$1"
shift
alias_names="$*"
```

**Start the log**
```bash
echo "$(date +'%T')" "$(date +'%F')" "Setting hostnames: $all_hostnames"
```

**Set the primary hostname in the container**
```bash
echo "$(date +'%T') Setting primary hostname."
echo "$default_hostname" | tee /etc/hostname >/dev/null
hostname -F /etc/hostname
```

**Regenerate the hosts file for the container.**
```bash
echo "$(date +'%T') Updating hosts file."
cat <<EOF | tee /etc/hosts >/dev/null
# IP4
127.0.0.1          $all_hostnames localhost
10.0.0.1           lxchost

# IP6
::1                $all_hostnames ip6-localhost ip6-loopback
ff02::1            ip6-allnodes
ff02::2            ip6-allrouters

EOF
```

**Update an Apache configuration, if available**
Pretty much all containers should have at most one Apache site configuration. There may be the occasional exception, which will need to be handled by a sysop. In all other cases, we can automatically fix an Apache config.
```bash
apache_config="$(find /etc/apache2/sites-available -maxdepth 1 -type f -regex '.*/.*[A-Za-z0-9-]+\.[a-z]+\.conf$')"
count="$(echo -n "$apache_config" | grep -c '^')"
if [ "$count" -eq 0 ]; then
    echo "$(date +'%T') No Apache config files found; skipping reconfiguration."
elif [ "$count" -gt 1 ]; then
    echo "$(date +'%T') More than one Apache config file was found; skipping reconfiguration."
else
    echo "$(date +'%T') Updating Apache configuration at $apache_config"
    sed -i 's/\(\s*#\?\s*ServerName\s\+\).*$/\1'"$default_hostname"'/g' "$apache_config"
    sed -i 's/\(\s*#\?\s*ServerAlias\s\+\).*$/\1'"$alias_names"'/g' "$apache_config"
fi
if ! apachectl configtest; then
    fail "'apachectl configtest' failed; sysop intervention is required."
fi
apachectl graceful
```

**Done.**
```bash
echo "$(date +'%T') Hostname configuration completed."
```


## TODO

* There should probably be some sanity-checking done on the hostnames parameter