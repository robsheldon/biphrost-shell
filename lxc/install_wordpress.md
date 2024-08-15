# Install Wordpress

A fully automated Wordpress installation. Assumes apache, mysql, and php are already installed and configured.

**Get the hostname and site root**
```bash
hostname="$(needopt hostname -p "Enter the default hostname WordPress will be using:" -m '^[A-Za-z0-9.-]+$')"
if [ -z "$hostname" ]; then
    exit 1
fi
site_root="$(find /srv/www -maxdepth 2 -mindepth 2 -type d -name public_html -empty | head -n 1)"
if [ -z "$site_root" ]; then
    fail "Can't find an empty public_html"
elif [ ! -d "$site_root" ]; then
    fail "Found $site_root but it's not a directory?!"
fi
```

**Initialize some required values**
The WordPress installation will need to have the correct ownership and permissions created and a new MySQL database needs to be created. The MySQL database name is based on the site's default hostname; the LXC environment assumes one-site-per-container, but the regular expression will extract the first two dot-delimited parts of a hostname (ignoring a "www") and use that as the database name. Examples: `www.mysite.com` becomes `mysite_com`, `test.mysite.com` becomes `test_mysite`, and `baz.blogs.mysite.com` becomes `baz_blogs`.
```bash
owner="$(find "$site_root" -maxdepth 0 -printf '%u')"
group="$(find "$site_root" -maxdepth 0 -printf '%g')"
dbname="$(echo "$hostname" | grep -oP '^(www\.)?\K[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+(?>=\.)?' | tr '.-' '_')"
dbuser="$dbname"
dbpass="$(random_string)"
```

**Tune MySQL**
A number of themes and plugins have some amazingly bad database queries built in to them: nested joins on large tables with no indexes, for example. These queries can run for a long time (minutes to hours), much longer than a WordPress page load, and gradually accumulate until MySQL consumes all available CPU and memory resources. We can prevent the resource exhaustion by imposing a reasonable query execution time limit in the MySQL configuration.
```bash
grep -qE '^#*\s*max_statement_time\s*=' /etc/mysql/conf.d/mysql.cnf || echo 'max_statement_time        = 30' | sudo tee -a /etc/mysql/conf.d/mysql.cnf >/dev/null
sudo sed -i 's/^#*\s*max_statement_time\s*.*$/max_statement_time        = 30/' /etc/mysql/conf.d/mysql.cnf
sudo service mysql restart && sleep 1
```

**Create the MySQL database**
Annoyingly, in MySQL "ALL PRIVILEGES" doesn't actually include all privileges, and the grant command can't be one-liner'd without causing an error. In WordPress's case, the privileges need to be global anyway.
```bash
cat <<EOF | sudo mysql
CREATE DATABASE \`$dbname\`;
CREATE USER '$dbuser'@localhost IDENTIFIED BY '$dbpass';
GRANT ALL PRIVILEGES ON \`$dbname\`.* TO '$dbuser'@localhost;
GRANT ALTER ROUTINE, CREATE ROUTINE, EXECUTE ON *.* TO '$dbuser'@localhost;
FLUSH PRIVILEGES;
EOF
```

**Install wp-cli**
```bash
wget -O - https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar | sudo tee /usr/local/bin/wp >/dev/null
sudo chmod 0755 /usr/local/bin/wp
```

**Download and configure the latest version of WordPress**
Because of https://github.com/wp-cli/config-command/issues/141 (and the first bug report on this, way back in 2017, getting [dismissed](https://github.com/wp-cli/config-command/issues/31)), a `cd` command is required instead of using `--path` with `wp`.
...and then, of course, `cd` needs to be followed with a `|| fail`, because bash and shellcheck and barf.
```bash
/usr/local/bin/wp core download --path="$site_root" --allow-root
cd "$site_root" || fail "cd \"$site_root\""
/usr/local/bin/wp core config --dbhost="localhost:/var/run/mysqld/mysqld.sock" --dbname="$dbname" --dbuser="$dbuser" --dbpass="$dbpass" --allow-root
```

**Set the proper ownership and permissions on everything in this directory**
```bash
sudo find "$site_root" -type d -exec chmod 0750 '{}' \;
sudo find "$site_root" -type f -exec chmod 0640 '{}' \;
sudo chown -R "$owner":"$group" "$site_root"
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
/usr/local/bin/wp --path="$site_root" --raw --quiet config set DISABLE_WP_CRON true
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
