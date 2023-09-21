# Add an ssh key to a container (and get its ssh access config)

This adds an ssh key to the specified container. If the container doesn't already have ssh access enabled, this will enable it. The ssh configuration that the user will need for connecting to the container will be echoed. Usage: `echo my_public_key | sudo biphrost --info user@domain.com ssh add key lxcNNNN`

**Initialization**
Retrieve the username argument (required). This will replace the comment part of the public key before it's added to the lxc host.
```bash
user_info="$(needopt info)"
```

Get the name of the container. Should be passed as the next argument directly after the name of the script.
```bash
if [ "${*:1:3}" = "ssh add key" ]; then shift; shift; shift; fi
if [ "$#" -lt 1 ]; then
    echo "NOTFOUND"
	exit 0
fi
container="$1"
shift
```

Verify that the container exists and is running.
```bash
case $(biphrost -b status "$container") in
    RUNNING)
    ;;
    *)
        fail "Not running: $container"
    ;;
esac
```

Retrieve the supplied key from stdin and replace its comment section (if it exists) with the user info.
```bash
public_key="$(grep -o '^ssh-rsa [A-Za-z0-9+=/]*' </dev/stdin) $user_info $(date '+%Y-%m-%d')"
```


**Add this key to the container**
```bash
echo "$public_key" | sudo -u "$container" lxc-unpriv-attach -n "$container" -e -- sh -c "mkdir -p /home/$container/.ssh && tee -a /home/$container/.ssh/authorized_keys >/dev/null && chown -R $container:$container /home/$container/.ssh && chmod 0700 /home/$container/.ssh && chmod 0600 /home/$container/.ssh/authorized_keys"
```

**Add the container to the host's knockd config if it doesn't exist already**
```bash
if grep -oq '^\['"$container"'\]$' /etc/knockd.conf; then
    read -r knock1 knock2 knock3 <<< "$(grep -A5 "$container" /etc/knockd.conf | grep -Po '([0-9]+:udp,?)*' | grep -Po '[0-9]+' | tr -dc '0-9\n' | grep -Po '[0-9 ]+' | tr '\n' ' ')"
else
    lxcip="$(grep "\\b$container\\b" /etc/hosts | grep -oE '([0-9.]+){3}\.[0-9]+(?\b)')"
    { read -r knock1; read -r knock2; read -r knock3; } < <(tr -dc '0-9' </dev/urandom | head -c 1000 | grep -o '[2-8][0-9][0-9][0-9]' | head -n 3)
    cat <<EOF | sudo tee -a /etc/knockd.conf >/dev/null

[$container]
    sequence      = $knock1:udp,$knock2:udp,$knock3:udp
    seq_timeout   = 10
    cmd_timeout   = 5
    start_command = /usr/sbin/iptables -t nat -A PREROUTING -p tcp -s %IP% --dport 22 -j DNAT --to-destination $lxcip:22
    stop_command  = /usr/sbin/iptables -t nat -D PREROUTING -p tcp -s %IP% --dport 22 -j DNAT --to-destination $lxcip:22
EOF
    sudo service knockd restart
fi
```

**Return the ssh configuration for this container**
```bash
primary_name="$(biphrost -b get hostnames "$container" | head -n 1)"
echo "Host $primary_name"
echo "    HostName $(biphrost -b get hostip)"
echo "    User $container"
echo "    HostKeyAlias $primary_name"
echo "    IdentityFile /path/to/private/key"
echo "    ProxyCommand sh -c \"knock -u -d 100 %h ${knock1} ${knock2} ${knock3}; sleep 1; nc %h %p\""
echo "    ConnectTimeout 10"
echo "    ConnectionAttempts 1"
```


## todo

* Shouldn't add duplicate keys -- check to see if a specified key already exists in the container's ssh config before adding it.