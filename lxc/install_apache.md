# Install Apache

```bash
echo "Installing Apache"
```

**Start the log**
```bash
echo "$(date +'%T')" "$(date +'%F')" "Installing Apache"
```

## Install and Configure Apache

**Create the `/srv/www` directory**
```bash
sudo mkdir -p /srv/www
```

**Create the `www-users` group**
```bash
sudo addgroup www-users
```

**Install Apache packages**
...and also `patch`, because it's required for a config file update below.
```bash
sudo apt-get -y install apache2 libapache2-mod-security2 patch cron >/dev/null
```

**Make sure Apache is using mpm_event and other required modules are enabled.**
```bash
sudo a2enmod mpm_event rewrite ssl proxy_fcgi
```

**Enable support for `index.shtml`**
This is super uncommon anymore but occasionally some software will try to use it and tracking this down again when it breaks is annoying.
```
sudo sed -i '/DirectoryIndex/ s/$/ index.shtml/' /etc/apache2/mods-available/dir.conf
```

**Make Apache a little quieter.**
By default, Apache announces some operating system and environmental information that really doesn't need to be announced. This config update disables that behavior. It doesn't make the server more secure against a dedicated adversary but it does prevent the server's software version information from getting indexed by bots.
```bash
cat <<'EOF' | sudo tee /etc/apache2/conf-available/httpd.conf
<IfModule mpm_event_module>
    KeepAlive On
    KeepAliveTimeout 2
    MaxKeepAliveRequests 500

    ThreadsPerChild 20
    ServerLimit 15
    MaxRequestWorkers 300
    MaxSpareThreads 200
    MaxConnectionsPerChild 10000
</IfModule>

<Directory /srv/>  
    Options Indexes FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>

ServerTokens Prod
ServerSignature Off
EOF
sudo a2enconf httpd
```

**Ensure that deflate is enabled**
```bash
sudo a2enmod deflate
```

**If this is inside a container, then set up mod_remoteip**
Apache servers running inside containerized hosts should assume that the upstream host is acting as a proxy for web traffic. Without `mod_remoteip`, containers will always see the wrong IP address for the request.
```bash
cat <<'EOF' | sudo tee /etc/apache2/conf-available/remoteip.conf
RemoteIPHeader X-Forwarded-For
RemoteIPTrustedProxy 10.0.0.1
EOF
if hostname | grep -q '^lxc[0-9]\+$'; then
    sudo a2enconf remoteip
    sudo a2enmod remoteip
    sudo service apache2 restart
fi
```

**Configure cron to kick Apache every night**
Apache has some gradual, long-term memory leaks that can cause strange behaviors on hosts with moderate traffic and long uptimes.
```bash
sudo EDITOR=cat crontab -e 2>/dev/null | cat - <(echo; echo '0 1 * * * /usr/sbin/apachectl graceful') | sudo crontab -
```

**Set up logrotate**
You probably don't want the access.log and error.log files for all your sites to just grow and grow and grow. Hopefully you're doing offsite backups too, and unrotated log files can make a small mess of that. Let's tell logrotate to handle the log files for hosted sites:
```bash
cat <<'EOF' | sudo tee /etc/logrotate.d/websites
/srv/www/*/logs/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    dateext
    notifempty
    create 600 root root
    sharedscripts
    postrotate
        if /etc/init.d/apache2 status >/dev/null; then
            service apache2 graceful >/dev/null
        fi
    endscript
    prerotate
        if [ -d /etc/logrotate.d/httpd-prerotate ]; then
            run-parts /etc/logrotate.d/httpd-prerotate
        fi
    endscript
}
EOF
```

