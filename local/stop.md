# Stop a container

This command will attempt to stop a container in any state and wait until its status **is not** `RUNNING` (as reported by [[status]]).

This is a simpler implementation than [[start]]; we don't need to care if the container is currently in an `ERROR` state. If the `lxc-stop` command fails for some reason, the only failure mode we care about is that the container is stuck in a `RUNNING` state. All other states are considered equivalent to `STOPPED`.

Get the name of the container. Should be passed as the next argument directly after the name of the script.
```bash
shift
if [ "$#" -lt 1 ]; then
    fail "No container specified"
fi
container="$1"
shift
```

Get the container's current status.
```bash
status="$(biphrost -b status "$container")"
```

If the container isn't located on this system, fail.
```bash
if [ "$status" = "NOTFOUND" ]; then
    fail "Container $container was not found"
fi
```

If the container is already stopped, do nothing.
```bash
if [ "$status" = "STOPPED" ]; then
    exit 0
fi
```

Otherwise, try to stop it and wait for its status to **not** be `RUNNING`. The only other failure mode here is `NOTFOUND`, because that would be weird and should probably raise an alarm.
```bash
start_time="$(date '+%s')"
sudo -u "$container" lxc-stop -n "$container" 2>/dev/null
while [ "$(date '+%s' -d "$start_time seconds ago")" -lt 60 ]; do
    status="$(biphrost -b status "$container")"
    case "$status" in
        RUNNING)
            ;;
        NOTFOUND)
            fail "$container has disappeared?!"
            ;;
        *)
            exit 0
            ;;
    esac
    sleep 1
done
fail "Timeout expired while waiting for $container to stop"
```