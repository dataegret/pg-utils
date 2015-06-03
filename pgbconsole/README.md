### README: pgbconsole
pgbConsole is the top-like console for Pgbouncer - PostgreSQL connection pooler.

#### Features:
- top-like interface
- show information about client/servers connections, pools/databases info and statistics.
- ability to perform admin commands, such as pause, resume, reload and others.
- ability to show log files or edit configuration in local pgbouncers.
- see details in doc directory.

#### Install notes:

#### Install from sources:
- install git, make, gcc, postgresql devel and ncurses devel packages

```
$ git clone https://github.com/lesovsky/pgbconsole
$ cd pgbconsole
$ make
$ sudo make install
$ pgbconsole
```
#### Known issues:
- Pgbouncer service restart not supported.
- Edit configuration supported only for local pgbouncers.
- Show log files supported only for local pgbouncers.
- Log-file screen displayed wrong when window enlarged (use L hotkey to reopen and redraw log).

#### Todo:
- add simultaneous pause/resume/reload for all pgbouncers (hotkey for common menu, and choose an option).
- add full log viewing with PAGER (small l hotkey).
- save color mappings per console into .pgbrc.
