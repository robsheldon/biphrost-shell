#!/bin/bash


# Do not modify this file! This file is automatically generated from the source
# file at /work/development/biphrost-shell/lxc/install_php.md.
# Modify that file instead.
# source hash: 05b1779696d911adf7198ed06d013a61

# begin-golem-injected-code

# Use any of these as necessary.
# Further reading on "$0" vs "$BASH_SOURCE" &etc.:
# https://stackoverflow.com/a/35006505
# https://stackoverflow.com/a/29835459
# shellcheck disable=SC2034
mypath=$(readlink -m "${BASH_SOURCE[0]}")
# shellcheck disable=SC2034
myname=$(basename "$mypath")
# shellcheck disable=SC2034
mydir=$(dirname "$mypath")
# shellcheck disable=SC2034
myshell=$(readlink /proc/$$/exe)

# Exit with an error if an undefined variable is referenced.
set -u

# If any command in a pipeline fails, that return code will be used as the
# return code for the whole pipeline.
set -o pipefail

# Halt with a non-zero exit status if a TERM signal is received by this PID.
# This is used by the fail() function along with $scriptpid.
trap "exit 1" TERM


##
# Return the filename component of a path; this is identical to calling
# "basename [path]"
#
path_filename () {
    local path=""
    path=$(realpath -s -m "$1")
    echo "${path##*/}"
}


##
# Return the parent directory of a path; this is identical to calling
# "dirname [path]", but it also cleans up extra slashes in the path.
#
path_directory () {
    local filename=""
    filename=$(path_filename "$1")
    realpath -s -m "${1%"$filename"}"
}


##
# Return the basename of the filename component of a path. For example, return
# "my_file" from "/path/to/my_file.txt".
#
path_basename () {
    local filename="" base="" ext=""
    filename=$(path_filename "$1")
    base="${filename%%.[^.]*}"
    ext="${filename:${#base} + 1}"
    if [ -z "$base" ] && [ -n "$ext" ]; then
        echo ".$ext"
    else
        echo "$base"
    fi
}


##
# Return the extension (suffix) of the filename component of a path. Example:
# return ".tar.gz" for "my_file.tar.gz", and "" for ".test".
#
path_extension () {
    local filename="" basename=""
    filename=$(path_filename "$1")
    basename=$(path_basename "$filename")
    echo "${filename##"$basename"}"
}


##
# Generate a pseudorandom string. Accepts an argument for the length of the
# string; if no string length is provided, then it defaults to generating a
# string between 12 and 25 characters long.
#
# Similar-looking characters are filtered out of the result string.
#
# shellcheck disable=SC2120
random_string () {
    local -i num_chars=0
    if [ $# -gt 0 ]; then
        num_chars=$1
    else
        num_chars=$((12 + RANDOM % 12))
    fi
    tr -dc _A-Z-a-z-0-9 < /dev/urandom | tr -d '/+oO0lLiI1\n\r' | head -c $num_chars
}


##
# Write a message to stderr and continue execution.
#
warn () {
    echo "Warning: $*" | fmt -w 80 >&2
}


##
# Write a message to stderr and exit immediately with a non-zero code.
#
fail () {
    echo "ERROR: $*" | fmt -w 80 >&2
    pkill -TERM -g $$ "$myname" || kill TERM $$ >/dev/null 2>&1
    exit 1
}


##
# Ask the user a question and process the response, with options for defaults
# and timeouts.
#
ask () {
    # Options:
    #     --timeout N:     time out if there's no input for N seconds.
    #     --default ANS:   use ANS as the default answer on timeout or
    #                      if an empty answer is provided.
    #     --required:      don't accept a blank answer. Use this parameter
    #                      to make ask() accept any string.
    #
    # ask() gives the answer in its exit status, e.g.,
    # if ask "Continue?"; then ...
    local ans="" default="" prompt=""
    local -i timeout=0 required=0

    while [ $# -gt 0 ] && [[ "$1" ]]; do
        case "$1" in
            -d|--default)
                shift
                default=$1
                if [[ ! "$default" ]]; then warn "Missing default value"; fi
                default=$(tr '[:upper:]' '[:lower:]' <<< "$default")
                if [[ "$default" = "yes" ]]; then
                    default="y"
                elif [[ "$default" = "no" ]]; then
                    default="n"
                elif [ "$default" != "y" ] && [ "$default" != "n" ]; then
                    warn "Illegal default answer: $default"
                fi
                shift
            ;;

            -t|--timeout)
                shift
                if [[ ! "$1" ]]; then
                    warn "Missing timeout value"
                elif [[ ! "$1" =~ ^[0-9][0-9]*$ ]]; then
                    warn "Illegal timeout value: $1"
                else
                    timeout=$1
                fi
                shift
            ;;

            -r|--required)
                shift
                required=1
            ;;

            -*)
                warn "Unrecognized option: $1"
            ;;

            *)
                break
            ;;
        esac
    done

    # Sanity checks
    if [[ $timeout -ne 0  &&  ! "$default" ]]; then
        warn "ask(): Non-zero timeout requires a default answer"
        exit 1
    fi
    if [ $required -ne 0 ]; then
        if [ -n "$default" ] || [ "$timeout" -gt 0 ]; then
            warn "ask(): 'required' is not compatible with 'default' or 'timeout' parameters."
            exit 1
        fi
    fi
    if [[ ! "$*" ]]; then
        warn "Missing question"
        exit 1
    fi

    prompt="$*"
    if [ "$default" = "y" ]; then
        prompt="$prompt [Y/n] "
    elif [ "$default" = "n" ]; then
        prompt="$prompt [y/N] "
    elif [ $required -eq 1 ]; then
        prompt="$prompt (required) "
    else
        prompt="$prompt [y/n] "
    fi


    while [ -z "$ans" ]
    do
        if [[ $timeout -ne 0 ]]; then
            if ! read -r -t "$timeout" -p "$prompt" ans </dev/tty; then
                ans=$default
                echo
            else
                # Turn off timeout if answer entered.
                timeout=0
                if [[ ! "$ans" ]]; then ans=$default; fi
            fi
        else
            read -r -p "$prompt" ans <"$(tty)"
            if [[ ! "$ans" ]]; then
                if [ $required -eq 1 ]; then
                    warn "An answer is required."
                    ans=""
                else
                    ans=$default
                fi
            elif [ $required -eq 0 ]; then
                ans=$(tr '[:upper:]' '[:lower:]' <<< "$ans")
                if [ "$ans" = "yes" ]; then
                    ans="y"
                elif [ "$ans" = "no" ]; then
                    ans="n"
                fi
            fi 
        fi

        if [ $required -eq 0 ]; then
            if [ "$ans" != 'y' ] && [ "$ans" != 'n' ]; then
                warn "Invalid answer. Please use y or n."
                ans=""
            fi
        fi
    done

    if [ $required -eq 1 ]; then
        echo "$ans"
        return 0
    fi

    [[ "$ans" = "y" || "$ans" == "yes" ]]
}


##
# Return the value of a named option passed from the commandline.
# If it doesn't exist, exit with a non-zero status.
# This function can be invoked like so:
#     if var="$(loadopt "foo")"; then...
# 
loadopt () {
    local varname="$1" value=""
    declare -i found=1
    # Run through the longopts array and search for a "varname".
    for i in "${longopts[@]}"; do
        if [ $found -eq 0 ]; then
            value="$i"
            break
        fi
        if [ "$i" = "--$varname" ]; then
            # Matched varname, set found here so that the next loop iteration
            # picks up varname's value.
            found=0
        fi
    done
    echo "$value"
    return $found
}


##
# Require a named value from the user. If the value wasn't specified as a longopt
# when the script was invoked, then needopt() will call ask() to request the value
# from the user. Use this to get required values for your scripts.
#
needopt () {
    # Usage:
    #     varname=$(needopt varname -p "Prompt to the user" -m [regex])
    local varname="" prompt="" match="" i="" found="" value=""
    while [ $# -gt 0 ] && [[ "$1" ]]; do
        case "$1" in
            -p)
                shift
                if [ $# -gt 0 ]; then
                    prompt="$1"
                    shift
                fi
            ;;
            -m)
                shift
                if [ $# -gt 0 ]; then
                    match="$1"
                    shift
                fi
            ;;
            -*)
                warn "Unrecognized option: $1"
            ;;
            *)
                if [ -z "$varname" ]; then
                    varname="$1"
                    shift
                else
                    fail "needopt(): Unexpected value: $1"
                fi
            ;;
        esac
    done
    if [ -z "$varname" ]; then
        fail "needopt(): No varname was provided"
    fi
    if [ -z "$prompt" ]; then
        prompt="$varname"
    fi
    if ! value="$(loadopt "$varname")" || [[ ! $value =~ $match ]]; then
        while true; do
            value="$(ask -r "$prompt")"
            if [ -n "$value" ] && [[ $value =~ $match ]]; then
                break
            elif [ -n "$match" ]; then
                warn "needopt(): this value doesn't match the expected regular expression: $match"
            fi
        done
    fi
    # printf -v "$varname" '%s' "$value"
    echo "$value"
    return 0
}


# Process arguments. Golem will load any "--variable value" pairs into the
# "longopts" array. Your command script can then call the needopt() function to
# load this value into a variable.
# Example: if your command script needs a "hostname" value, the user can supply
# that with, "golem --hostname 'host.name' your command", and the "your_command.sh"
# file can use "hostname=needopt(hostname)" to create a variable named "hostname"
# with the value "host.name" (or ask the user for it).
declare -a longopts=()
declare -a args=()
while [ $# -gt 0 ] && [[ "$1" ]]; do
    case "$1" in
        --)
            # Stop processing arguments.
            break
            ;;
        --*)
            longopts+=("$1")
            shift
            if [ $# -lt 1 ] || [[ "$1" =~ ^--.+ ]]; then
                longopts+=("")
            else
                longopts+=("$1")
                shift
            fi
            ;;
        *)
            args+=("$1")
            shift
            ;;
    esac
done
# Reset the arguments list to every argument that wasn't a --longopt.
set -- "${args[@]}"
unset args


################################################################################
#                                                                              #
#    Main program                                                              #
#                                                                              #
################################################################################

# end-golem-injected-code

# This script appears to require sudo, so make sure the user has the necessary access.
# If they do, then run a sudo command now so that script execution doesn't trip
# on a password prompt later.
if ! groups | grep -qw '\(sudo\|root\)'; then
    fail "It looks like this command script requires superuser access and you're not in the 'sudo' group"
elif [ "$(sudo whoami </dev/null)" != "root" ]; then
    fail "Your 'sudo' command seems to be broken"
fi

php_version=$(needopt version -p "PHP Version (7.3, 7.4, 8.0, 8.1, etc.):" -m '^[78]\.+[0-9]$')
echo "$(date +'%T')" "$(date +'%F')" "Installing PHP $php_version"
IFS=$'\n' php_services=("$(systemctl list-unit-files | grep '.*php\S\+\s\+enabled\s' | grep -v sessionclean | cut -d ' ' -f 1)")
echo "$(date +'%T')" "Disabling php-related services..."
while read -r service; do
    sudo systemctl stop "$service"
    sudo systemctl disable "$service"
done < <(grep -sl '^\s*#\?\s*ExecStart=[a-zA-Z0-9._/-]\+/php-fpm[0-9.]\+\s\+' /etc/systemd/system/*)
echo "$(date +'%T')" "Removing old php packages..."
sudo apt-get -y remove 'php*' >/dev/null 2>&1
echo "$(date +'%T')" "Updating sury.org key..."
sudo apt-get -y install wget ca-certificates apt-transport-https gnupg >/dev/null
sudo wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg && sudo chmod 0644 /etc/apt/trusted.gpg.d/php.gpg
os_release=$(dpkg --status tzdata | grep Provides | cut -f2 -d'-')
echo "deb https://packages.sury.org/php/ $os_release main" | sudo tee /etc/apt/sources.list.d/php.list
if sudo apt-get -y update >/dev/null && sleep 1; then
    echo "Retrieved package updates"
else
    fail "sudo apt-get update"
fi
echo "$(date +'%T')" "Installing php $php_version packages..."
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
echo "$(date +'%T')" "Installing composer..."
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
echo "$(date +'%T')" "Cleaning up:"
if systemctl list-unit-files | grep -q "php$php_version-fpm\\.service"; then
    echo "$(date +'%T')" "Disabling php$php_version-fpm default service..."
    sudo systemctl stop "php$php_version-fpm"
    sudo systemctl disable "php$php_version-fpm"
    unit_path="$(systemctl cat "php$php_version-fpm" 2>/dev/null | grep -oP '^#\s*\K/.*/php[0-9.]+-fpm.service')"
    if [ -n "$unit_path" ] && [ -f "$unit_path" ]; then
        sudo rm "$unit_path"
    fi
    sudo systemctl daemon-reload
fi
echo "$(date +'%T')" "Copying pool configuration files..."
sudo find /etc/php/*/fpm/pool.d/ -type f | grep -v "/$php_version/" | xargs -I {} sudo cp {} "/etc/php/$php_version/fpm/pool.d/"
echo "$(date +'%T')" "Updating pool configuration files..."
sudo sed -i -e 's|^\(\s*;*\s*listen\s*=\s*[a-zA-Z0-9/_-]\+\)[0-9]\.[0-9]\(-fpm.*\)$|\1'"$php_version"'\2|' "/etc/php/$php_version/fpm/pool.d/"*
php_fpm_path="$(sudo which php-fpm"$php_version")"
if [ -n "$php_fpm_path" ]; then
    echo "$(date +'%T')" "Updating php-fpm service files..."
    # Update an ExecStart= line that includes a parth to an fpm-config.
    # It might make more sense to break these up into a couple of different sed commands.
    sudo sed -i -e 's|^\(\s*#*\s*ExecStart=\)/usr/s\?bin/php-fpm[0-9.]\+\s\+\(.*/etc/php/\)[0-9.]\+\(.*\)$|\1'"$php_fpm_path"' \2'"$php_version"'\3|' /etc/systemd/system/*.service
    sudo systemctl daemon-reload
fi
echo "$(date +'%T')" "Restarting php services..."
for service in "${php_services[@]}"; do
    sudo systemctl restart "$service"
done
if command -v apachectl >/dev/null; then
    echo "$(date +'%T')" "Updating Apache site configurations..."
    sudo sed -i -e 's|\(\(php\)\?[-_]\?\)[0-9.]*\(-fpm\)|\2'"$php_version"'\3|' /etc/apache2/sites-available/*
    echo "$(date +'%T')" "Restarting Apache..."
    sudo apachectl graceful
fi
echo "$(date +'%T')" "Done!"
