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

**Download the latest version of WordPress**
```bash
wget -O - https://wordpress.org/latest.tar.gz | sudo tar -xz -C "$site_root" --strip-components=1
if [ ! -f "$site_root/wp-config-sample.php" ]; then
    fail "The Wordpress download seems to have failed; wp-config-sample.php was not found in $site_root"
fi
```

**Create the WordPress configuration file**
```bash
sudo mv "$site_root/wp-config-sample.php" "$site_root/wp-config.php"
sedstr="s/^define\\(\\s*'DB_NAME'.*$/define\\('DB_NAME', '$dbname'\\);/g"
sudo sed -i -r -e "$sedstr" "$site_root/wp-config.php"
sedstr="s/^define\\(\\s*'DB_USER'.*$/define\\('DB_USER', '$dbuser'\\);/g"
sudo sed -i -r -e "$sedstr" "$site_root/wp-config.php"
sedstr="s/^define\\(\\s*'DB_PASSWORD'.*$/define\\('DB_PASSWORD', '$dbpass'\\);/g"
sudo sed -i -r -e "$sedstr" "$site_root/wp-config.php"
sedstr="s/^define\\(\\s*'AUTH_KEY',.*$/define\\('AUTH_KEY',         '$(random_string 64)'\\);/g"
sudo sed -i -r -e "$sedstr" "$site_root/wp-config.php"
sedstr="s/^define\\(\\s*'SECURE_AUTH_KEY',.*$/define\\('SECURE_AUTH_KEY',  '$(random_string 64)'\\);/g"
sudo sed -i -r -e "$sedstr" "$site_root/wp-config.php"
sedstr="s/^define\\(\\s*'LOGGED_IN_KEY',.*$/define\\('LOGGED_IN_KEY',    '$(random_string 64)'\\);/g"
sudo sed -i -r -e "$sedstr" "$site_root/wp-config.php"
sedstr="s/^define\\(\\s*'NONCE_KEY',.*$/define\\('NONCE_KEY',        '$(random_string 64)'\\);/g"
sudo sed -i -r -e "$sedstr" "$site_root/wp-config.php"
sedstr="s/^define\\(\\s*'AUTH_SALT',.*$/define\\('AUTH_SALT',        '$(random_string 64)'\\);/g"
sudo sed -i -r -e "$sedstr" "$site_root/wp-config.php"
sedstr="s/^define\\(\\s*'SECURE_AUTH_SALT',.*$/define\\('SECURE_AUTH_SALT', '$(random_string 64)'\\);/g"
sudo sed -i -r -e "$sedstr" "$site_root/wp-config.php"
sedstr="s/^define\\(\\s*'LOGGED_IN_SALT',.*$/define\\('LOGGED_IN_SALT',   '$(random_string 64)'\\);/g"
sudo sed -i -r -e "$sedstr" "$site_root/wp-config.php"
sedstr="s/^define\\(\\s*'NONCE_SALT',.*$/define\\('NONCE_SALT',       '$(random_string 64)'\\);/g"
sudo sed -i -r -e "$sedstr" "$site_root/wp-config.php"
```

**Finally, set the proper ownership on everything in this directory.**
```bash
sudo chown -R "$owner":"$group" "$site_root"
```
