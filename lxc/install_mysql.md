# Install and Configure MySQL (using MariaDB)

## Description

This document installs [MariaDB](https://mariadb.org/), an open source drop-in replacement for MySQL. MariaDB should be binary-compatible with the MySQL ABI and it is the default installation candidate for mysql* packages in Debian.

MariaDB has been found to [perform slightly better than Percona](https://blog.kernl.us/2019/10/wordpress-database-performance-showdown-mysql-vs-mariadb-vs-percona/) in small installations, so it's a better pick for single-application containers and VPS environments. Percona may be a better choice for distributed database systems because of their greater focus on cluster support.

## Steps

**Install MariaDB**
MariaDB is present in Debian main repositories, so installation is straightforward:
```bash
sudo dpkg -l mariadb-server 2>/dev/null || sudo apt-get -y install mariadb-server >/dev/null
```

**Test passwordless login**
```bash
echo -e 'SELECT "OK";' | sudo mysql -s || { fail "Could not connect to the MySQL server process as root"; }
```

**Clean up**
```bash
sudo service mysql restart
```

## References

* https://dba.stackexchange.com/questions/305708/understanding-thread-pool-and-max-connection-in-mariadb
* https://mariadb.com/resources/blog/10-database-tuning-tips-for-peak-workloads/
* https://mariadb.com/kb/en/query-cache/
* https://stackoverflow.com/questions/45412537/should-i-turn-off-query-cache-in-mysql
* https://www.percona.com/doc/percona-server/8.0/performance/threadpool.html
* https://mariadb.com/kb/en/thread-pool-in-mariadb/
* https://stackoverflow.com/questions/40189226/how-to-make-mysql-use-less-memory
* https://dba.stackexchange.com/questions/27328/how-large-should-be-mysql-innodb-buffer-pool-size
* https://stackoverflow.com/questions/1733507/how-to-get-size-of-mysql-database
