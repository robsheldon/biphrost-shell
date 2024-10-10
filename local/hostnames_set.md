# Update the hostnames for a container

Updates local (lxc host) configuration with new hostnames for a container, and then invokes a `set hostnames` command to updat ethe configuration inside the container.

**Notes:**
* Primary hostname is the first hostname in the list (affects names listed in ssl cert)
* Need to update the container's `/etc/hosts`
* ...and the container's `hostname`
* An SSL cert update should *not* be triggered here; we allow users to add hostnames that may not yet be updated in DNS

**Parameters**
* `--hostnames` (required): the default hostnames to be applied to the container (replacing any other hostnames)
* `--target` (required): the container identifier that is getting its hostnames reconfigured
```bash
hostnames="$(needopt hostnames)"
target="$(needopt target -m '^lxc[0-9]{4}$')"
if [ "$(biphrost -b status "$target")" = "NOTFOUND" ]; then
    fail "Invalid container ID: $target"
fi
if [ ! -f /etc/nginx/sites-enabled/"$1" ]; then
    fail "No nginx configuration found for $target"
fi
```

**Validate the hostnames**
Ensure none of the hostnames match a "biphrost" pattern (that would be naughty). Any invalid hostnames will cause the entire operation to fail. The first hostname in the list becomes the default hostname.
```bash
default_hostname=""
for hostname in $hostnames; do
    echo "hostname: $hostname"
    if ! [[ "$hostname" =~ ^([A-Za-z0-9-]+\.)+[A-Za-z0-9-]+$ ]]; then
        fail "Invalid hostname: $hostname does not look like a routable network hostname"
    fi
    if [[ "$hostname" =~ "biphrost" ]]; then
        fail "Invalid hostname: $hostname (cannot contain 'biphrost')"
    fi
    if [ -z "$default_hostname" ]; then
        default_hostname="$hostname"
    fi
done
if [ -z "$default_hostname" ]; then
    fail "No valid hostnames were given"
fi
```

**Update the hostnames inside the container**
```bash
# shellcheck disable=SC2086
biphrost -b @"$target" set hostnames $hostnames
```

**Update the container's nginx configuration**
```bash
sed -i 's/\(\s*#\?\s*server_name \).*;$/\1'"$hostnames"';/g' /etc/nginx/sites-available/"$target"
sed -i 's|\(\s*#\?\s*ssl_certificate\s\+/home/'"$target"'/ssl/\).*\(/fullchain.pem;\)$|\1'"$default_hostname"'\2|g' /etc/nginx/sites-available/"$target"
sed -i 's|\(\s*#\?\s*ssl_certificate_key\s\+/home/'"$target"'/ssl/\).*\(/fullchain.pem;\)$|\1'"$default_hostname"'\2|g' /etc/nginx/sites-available/"$target"
```