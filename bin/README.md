## Simple scripts for routine actions
### check_replication_lag.pl

### generate_pgbouncer_userlist.sh

### slony_extract_schema_to_file.sh

### stuff-update.sh
This script updates your copy of pg_utils to the actual state. There are two ways for cloning the repository:
* `git pull` - just pulls new changes into the local directory
* wget/curl - downloads repository as the zip archive and unpacks it into the local directory.

### offlag.sh
Script to check lag of the local _running_ but  _offline_ (not available for
queries) database against the provided source:
- masterhost (should be reachable for postgres@postgres)
- WAL segment name (as found in the pg_wal directory)
- LSN, as reported by the pg_current_wal_lsn/pg_last_wal_replay_lsn functions).
