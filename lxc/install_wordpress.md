# Install Wordpress

A fully automated Wordpress installation.

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
wp core download --path="$site_root" --allow-root
cd "$site_root" || fail "cd \"$site_root\""
wp core config --dbhost="localhost" --dbname="$dbname" --dbuser="$dbuser" --dbpass="$dbpass" --allow-root
```

**Set the proper ownership and permissions on everything in this directory**
```bash
sudo find "$site_root" -type d -exec chmod 0750 '{}' \;
sudo find "$site_root" -type f -exec chmod 0640 '{}' \;
sudo chown -R "$owner":"$group" "$site_root"
```
