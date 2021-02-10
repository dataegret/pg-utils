## Simple scripts for routine actions

### check_replication_lag.pl
Check replication lag of the specified list of replicas.
By default, script will list all replicas and their current lag.
There is also cron-mode, that will be silent unless specified lag threshold is
reached.

Check help output of the script for more details.

### generate_pgbouncer_userlist.sh
Straightforward script to dump role into `userlist.txt` file of pgbouncer.

### slony_extract_schema_to_file.sh
Get schema dump without all the Slony-specific stuff.
Temporary database will be created to clean up Slony belongings.

### stuff-update.sh
This script updates your copy of pg_utils to the actual state. There are two ways for cloning the repository:
* `git pull` - just pulls new changes into the local directory
* wget/curl - downloads repository as the zip archive and unpacks it into the local directory.

### offlag.sh
Script to check lag of the local _running_ but  _offline_ (not available for
queries) database against the provided source:
- master_host, should be reachable for postgres@postgres
- WAL segment name as found in the pg_wal directory
- LSN, as reported by the pg_current_wal_lsn/pg_last_wal_replay_lsn functions.
