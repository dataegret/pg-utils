### README: pgbconsole
pgbConsole is the top-like console for Pgbouncer - PostgreSQL connection pooler.

#### Features:
- top-like interface
- show information about client/servers connections, pools/databases info and statistics.
- ability to perform admin commands, such as pause, resume, reload and others.
- ability to show log files or edit configuration in local pgbouncers.
- see details in doc directory.

#### Install notes:

##### Install on Ubuntu
- install PPA and update
```
$ sudo add-apt-repository ppa:lesovsky/pgbconsole
$ sudo apt-get update
$ sudo apt-get install pgbconsole
```
Debian users can create package using this [link](https://wiki.debian.org/CreatePackageFromPPA).

##### Install on RHEL/CentOS.
- install pgbConsole from Essential Kaos testing repo.
 
```
$ sudo yum install http://release.yum.kaos.io/x86_64/kaos-repo-6.8-0.el6.noarch.rpm
$ sudo yum --enablerepo=kaos-testing install pgbconsole
```

##### Install from sources:
- install git, make, gcc, postgresql devel and ncurses devel packages
```
$ git clone https://github.com/lesovsky/pgbconsole
$ cd pgbconsole
$ make
$ sudo make install
$ pgbconsole
```
#### Known issues:
- Consoles number limited by 8.
- Pgbouncer service restart not supported.
- Edit configuration supported only for local pgbouncers.
- Show log files supported only for local pgbouncers.
- Log-file screen displayed wrong when window size increased (use L hotkey to reopen and redraw log).

#### Todo:
- add simultaneous pause/resume/reload for all pgbouncers (hotkey for common menu, and choose an option).
- save color mappings per console into .pgbrc.
