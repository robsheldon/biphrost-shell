# Configure hostnames inside a container

This command gets invoked by a Biphrost local script, which has already handled hostname validation.

The primary hostname should be the first hostname provided in the argument list.

**TODO**
* Update Apache/etc. config in the container

**Load hostnames from argument list**
```bash
if [ "${*:1:2}" = "set hostnames" ]; then
    shift; shift
fi
if [ $# -lt 1 ]; then
    fail "No hostnames given"
fi
```

**Get the default hostname from the argument list**
This is expected to be the first argument in the list.
```bash
default_hostname="$1"
hostnames="$*"
```

**Start the log**
```bash
echo "$(date +'%T')" "$(date +'%F')" "Setting hostnames: $hostnames"
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
127.0.0.1          $hostnames localhost
10.0.0.1           lxchost

# IP6
::1                $hostnames ip6-localhost ip6-loopback
ff02::1            ip6-allnodes
ff02::2            ip6-allrouters

EOF
```

**Done.**
```bash
echo "$(date +'%T') Hostname configuration completed."
```


## TODO

* There should probably be some sanity-checking done on the hostnames parameter