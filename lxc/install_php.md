# Install PHP

## Description

This configuration allows a server to seamlessly run multiple versions of PHP -- including PHP 5, for as long as it's still available.

**Required parameters**
```bash
php_version=$(needopt version -p "PHP Version (7.3, 7.4, 8.0, 8.1, etc.):" -m '^[78]\.+[0-9]$')
```


## Prep work

**Get a list of currently enabled php services**
We'll need to know which services to re-enable later.
```bash
IFS=$'\n' php_services=("$(systemctl list-unit-files | grep '.*php\S\+\s\+enabled\s' | grep -v sessionclean | cut -d ' ' -f 1)")
```

**Stop any existing php-fpm services**
This uses a different approach to finding php-related services than the one above that populates `$php_services`, but I *think* that's what we want. The first version finds any service with `php` in its name that is *currently enabled*, regardless of its service file location; this version will stop any service that invokes `php-fpm`, regardless of whether it's enabled or not, but only looks under `/etc/systemd/system`. I don't think we win anything by trying to unify the two approaches; they're trying to do different things. Let's wait for an edge case to appear where one or the other doesn't work and address it then.
```bash
while read -r service; do
    sudo systemctl stop "$service"
    sudo systemctl disable "$service"
done < <(grep -sl '^\s*#\?\s*ExecStart=[a-zA-Z0-9._/-]\+/php-fpm[0-9.]\+\s\+' /etc/systemd/system/*)
```

**Remove any existing php installations**
```bash
sudo apt-get -y remove 'php*' >/dev/null 2>&1
```


## Installation

**Use packages from [[ https://deb.sury.org/ | sury.org ]]:**
```bash
sudo apt-get -y install wget ca-certificates apt-transport-https gnupg >/dev/null
sudo wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg && sudo chmod 0644 /etc/apt/trusted.gpg.d/php.gpg
os_release=$(dpkg --status tzdata | grep Provides | cut -f2 -d'-')
echo "deb https://packages.sury.org/php/ $os_release main" | sudo tee /etc/apt/sources.list.d/php.list
```

**Update the package repositories**
```bash
if sudo apt-get -y update >/dev/null && sleep 1; then
    echo "Retrieved package updates"
else
    fail "sudo apt-get update"
fi
```

**Install PHP packages**
Per [the official documentation](https://github.com/oerdnj/deb.sury.org/wiki/Frequently-Asked-Questions#install-php-package-without-apache2-requirement), avoid installing `php"$php_version"` (bare package name, without `-cgi`, `-cli`, etc.), because that adds Apache as a dependency, which might not be needed in all runtime environments.
```bash
case "$php_version" in
    8.*)
        sudo apt-get -y install php"$php_version"-{cgi,cli,fpm,bcmath,common,ctype,curl,exif,fileinfo,gd,gmp,imagick,imap,intl,ldap,mbstring,mysql,mysqlnd,opcache,pdo,pgsql,readline,soap,sqlite3,tidy,tokenizer,xml,xmlrpc,zip} >/dev/null || fail "sudo apt -y install [php packages...]"
        ;;
    7.1)
        sudo apt-get -y install php"$php_version"-{cgi,cli,fpm,bcmath,common,ctype,curl,exif,fileinfo,gd,gmp,imagick,imap,intl,json,ldap,mbstring,mcrypt,mysql,mysqlnd,opcache,pdo,pgsql,readline,soap,tidy,tokenizer,xml,xmlrpc,zip} >/dev/null || fail "sudo apt -y install [php packages...]"
        ;;
    *)
        sudo apt-get -y install php"$php_version"-{cgi,cli,fpm,bcmath,common,ctype,curl,exif,fileinfo,gd,gmp,imagick,imap,intl,json,ldap,mbstring,mysql,mysqlnd,opcache,pdo,pgsql,readline,soap,sqlite3,tidy,tokenizer,xml,xmlrpc,zip} >/dev/null || fail "sudo apt -y install [php packages...]"
        ;;
esac
echo "Installed PHP $php_version packages"
```
NOTE: mcrypt was removed in 7.2. Older applications may require it.

**Install Composer**
Adapted from the [official instructions](https://getcomposer.org/doc/faqs/how-to-install-composer-programmatically.md).
```bash
cd || fail "Can't change directory?"
EXPECTED_CHECKSUM="$(wget -q -O - https://composer.github.io/installer.sig)"
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
    rm composer-setup.php
    fail 'ERROR: Invalid installer checksum'
fi

php composer-setup.php --quiet
rm composer-setup.php
sudo mv composer.phar /usr/local/bin/composer && sudo chown root:root /usr/local/bin/composer
```


## Cleanup

**Disable the default php-fpm service**
This configuration is intended to have a php-fpm pool configuration created for each individual site. However, a recent change was made to the php-fpm installation process that causes it to install and enable a default global php-fpm service, which prevents the pool services from starting properly later. So, it needs to be disabled.
```bash
if systemctl list-unit-files | grep -q "php$php_version-fpm\\.service"; then
    sudo systemctl stop "php$php_version-fpm"
    sudo systemctl disable "php$php_version-fpm"
    unit_path="$(systemctl cat "php$php_version-fpm" 2>/dev/null | grep -oP '^#\s*\K/.*/php[0-9.]+-fpm.service')"
    if [ -n "$unit_path" ] && [ -f "$unit_path" ]; then
        sudo rm "$unit_path"
    fi
    sudo systemctl daemon-reload
fi
```

**Copy and update fpm pool config files**
We want to copy any php-fpm pool files that are *not* the default templates installed by the new version of php.
```bash
sudo find /etc/php/*/fpm/pool.d/ -type f | grep -v "/$php_version/" | xargs -I {} sudo cp {} "/etc/php/$php_version/fpm/pool.d/"
```

**Fix the path to the listening socket, if present.**
```bash
sudo sed -i -e 's|^\(\s*;*\s*listen\s*=\s*[a-zA-Z0-9/_-]\+\)[0-9]\.[0-9]\(-fpm.*\)$|\1'"$php_version"'\2|' "/etc/php/$php_version/fpm/pool.d/"*
```
TODO: May need to modify these files slightly if options change between php versions.

**Update any remaining php-fpm service files**
If the container is already hosting PHP sites, there should be one or more remaining fpm service files.
```bash
php_fpm_path="$(sudo which php-fpm"$php_version")"
if [ -n "$php_fpm_path" ]; then
    # Update an ExecStart= line that includes a parth to an fpm-config.
    # It might make more sense to break these up into a couple of different sed commands.
    sudo sed -i -e 's|^\(\s*#*\s*ExecStart=\)/usr/s\?bin/php-fpm[0-9.]\+\s\+\(.*/etc/php/\)[0-9.]\+\(.*\)$|\1'"$php_fpm_path"' \2'"$php_version"'\3|' /etc/systemd/system/*.service
fi
sudo systemctl daemon-reload
```

**Restart PHP services**
```bash
for service in "${php_services[@]}"; do
    sudo systemctl restart "$service"
done
```

**Update Apache site configuration files and restart Apache**
...if Apache is installed.
```bash
if command -v apachectl >/dev/null; then
    sudo sed -i -e 's|\(\(php\)\?[-_]\?\)[0-9.]*\(-fpm\)|\2'"$php_version"'\3|' /etc/apache2/sites-available/*
    sudo apachectl graceful
fi
```


## References

* [[ https://tecadmin.net/install-php7-on-debian/ | How To Install PHP (7.2, 7.1 & 5.6) on Debian 8 Jessie ]].

