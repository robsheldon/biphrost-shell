**First, find a site root**
Fail if the site root didn't come back with exactly one result.
```bash
if ! site_root="$(loadopt target)"; then
    site_root="$(find /srv/www -maxdepth 2 -mindepth 1 -type d -name public_html)"
    count=$(echo -n "$site_root" | grep -c '^')
    if [ "$count" -eq 0 ]; then
        fail "public_html not found"
    elif [ "$count" -gt 1 ]; then
        fail "too many public_html directories found under /srv/www!"
    fi
fi
```

**Next, ensure `wp` is available**
If it's not already installed, then verify that this is a WP site, and install it.
```bash
if ! which wp; then
    if [ -f "$site_root/wp-config.php" ]; then
        wget -O - https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar | sudo tee /usr/local/bin/wp >/dev/null
        sudo chmod 0755 /usr/local/bin/wp
    else
        fail "Not a WordPress site!"
    fi
fi
```

**Get site owner-user**
```bash
owner="$(find "$site_root" -maxdepth 0 -printf '%u')";
if [ -z "$owner" ]; then
    fail "Did not get a valid owner name for this site"
fi
group="$owner"    
```

**Retrieve dbname from wp config**
```bash
dbname="$(sudo -u "$owner" -- wp --path="$site_root" config get DB_NAME)"
if [ -z "$dbname" ]; then
    fail "Could not get dbname from wp config"
fi
```

**Create a systemd timer for WordPress core and plugin updates**
Automatically perform minor core, plugin, and theme updates between the hours of midnight and 2:00 am.
```bash
cat <<EOF | sudo tee /etc/systemd/system/wp-"${dbname}"-update.service >/dev/null
[Unit]
Description=WordPress automatic updates
After=network.target
Wants=wp-${dbname}-update.timer

[Service]
Type=oneshot
User=$owner
Group=$group
ExecStartPre=
ExecStart=/usr/local/bin/wp --path="$site_root" --skip-plugins --skip-themes --quiet --minor core update
ExecStart=/usr/local/bin/wp --path="$site_root" --quiet --minor --all plugin update
ExecStart=/usr/local/bin/wp --path="$site_root" --quiet --minor --all theme update

[Install]
WantedBy=multi-user.target
EOF
```

```bash
cat <<EOF | sudo tee /etc/systemd/system/wp-"${dbname}"-update.timer >/dev/null
[Unit]
Description=WordPress automatic update timer
Requires=wp-${dbname}-update.service

[Timer]
Unit=wp-${dbname}-update.service
OnCalendar=*-*-* 00:00:00
AccuracySec=2h

[Install]
WantedBy=timers.target
EOF
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable wp-"${dbname}"-update.service
sudo systemctl enable wp-"${dbname}"-update.timer
sudo systemctl start wp-"${dbname}"-update.timer
```

**Create a systemd timer to run WordPress cron**
WP cron is scheduled here to run every minute (with a 5 second variance) between 3:00am server time and 11:59pm server time. It does not run between midnight and 5:00am to prevent potential conflicts with the automatic update service.
```bash
cat <<EOF | sudo tee /etc/systemd/system/wp-"${dbname}"-cron.service >/dev/null
[Unit]
Description=WordPress Cron
After=network.target
Wants=wp-${dbname}-cron.timer

[Service]
Type=oneshot
User=$owner
Group=$group
ExecStartPre=
ExecStart=/usr/local/bin/wp --path="$site_root" --quiet cron event run --due-now

[Install]
WantedBy=multi-user.target
EOF
```

```bash
cat <<EOF | sudo tee /etc/systemd/system/wp-"${dbname}"-cron.timer >/dev/null
[Unit]
Description=WordPress Cron timer
Requires=wp-${dbname}-cron.service

[Timer]
Unit=wp-${dbname}-cron.service
OnCalendar=*-*-* 03..23:*:00
AccuracySec=5s

[Install]
WantedBy=timers.target
EOF
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable wp-"${dbname}"-cron.service
sudo systemctl enable wp-"${dbname}"-cron.timer
sudo systemctl start wp-"${dbname}"-cron.timer
sudo -u "$owner" -- /usr/local/bin/wp --path="$site_root" --raw --quiet config set DISABLE_WP_CRON true
```

**Create a systemd timer to periodically restart MySQL**
Pathologically poorly written WordPress plugins and themes will occasionally run MySQL queries that will hang around for a very long time, despite configuring MySQL to prevent this. Over time, the queries pile up, consuming MySQL's available memory, until it hangs. Disappointingly, the most effective fix for this that I've found so far is to restart MySQL every once in a while.

The MySQL restart is scheduled to happen after the WordPress updates should be completed and before WordPress cron is scheduled to start up again.
```bash
cat <<EOF | sudo tee /etc/systemd/system/mysql-restart.service >/dev/null
[Unit]
Description=Restart MySQL
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/systemctl try-restart mysql.service

[Install]
WantedBy=multi-user.target
EOF
```

```bash
case "$(shuf -i 1-5 -n 1)" in
    1)
        period="*-*-1,6,11,16,21,26 02:45:00"
        ;;
    2)
        period="*-*-2,7,12,17,22,27 02:45:00"
        ;;
    3)
        period="*-*-3,8,13,18,23,28 02:45:00"
        ;;
    4)
        period="*-*-4,9,14,19,24,29 02:45:00"
        ;;
    5)
        period="*-*-5,10,15,20,25,30 02:45:00"
        ;;
esac
cat <<EOF | sudo tee /etc/systemd/system/mysql-restart.timer >/dev/null
[Unit]
Description=MySQL Restart timer
Requires=mysql-restart.service

[Timer]
Unit=mysql-restart.service
OnCalendar=$period
AccuracySec=120s

[Install]
WantedBy=timers.target
EOF
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable mysql-restart.service
sudo systemctl enable mysql-restart.timer
sudo systemctl start mysql-restart.timer
```
