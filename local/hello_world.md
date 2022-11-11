# A "hello world" for testing

**List the containers on this host**
```bash
echo "user: $(whoami)"
echo "host: $(hostname --fqdn)"
echo "-----"
echo "Containers on this host:"
for container in $(find /home -maxdepth 1 -type d -name 'lxc*' -printf '%f\n' | sort); do
    printf '%s... ' "$container"
    status="$(sudo lxc-ls --fancy -F 'STATE' --filter="$container" | tail -n 1 | sed 's/ *$//')"
    printf '%s ' "$status"
    if [ "$status" = "RUNNING" ]; then
        attach_ok="$(biphrost -b @"$container" hello world)"
        printf '[%s]' "$attach_ok"
    fi
    echo
done
echo "-----"
echo "Hello, world."
```