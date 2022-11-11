# Return the status of a container

Should return a simple value of: "RUNNING", "STOPPED", "ERROR", "NOTFOUND", etc.

Get the name of the container. Should be passed as the next argument directly after the name of the script.
```bash
shift
if [ "$#" -lt 1 ]; then
    echo "NOTFOUND"
	exit 0
fi
container="$1"
shift
```

Get the container's current status.
```bash
status="$(sudo lxc-ls --fancy -F 'STATE' --filter="$container" 2>&1 | tail -n 1 | sed 's/ *$//')"
```

Do a little additional processing.
```bash
if [ -z "$status" ]; then
    echo "NOTFOUND"
elif [ "$status" = "Failed to load config for lxc0007" ]; then
    echo "ERROR"
else
    echo "$status"
fi
```