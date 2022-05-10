-- List active replication connections
SELECT client_addr       AS client
     , usename           AS user
     , application_name  AS name
     , state, sync_state AS mode, backend_xmin
     , (pg_wal_lsn_diff(CASE WHEN pg_is_in_recovery() THEN pg_last_wal_replay_lsn() ELSE pg_current_wal_lsn() END,sent_lsn)/1024.0/1024)::numeric(10,1) AS pending_mb
     , (pg_wal_lsn_diff(sent_lsn,write_lsn)/1024.0/1024)::numeric(10,1)                                                                                 AS write_mb
     , (pg_wal_lsn_diff(write_lsn,flush_lsn)/1024.0/1024)::numeric(10,1)                                                                                AS flush_mb
     , (pg_wal_lsn_diff(flush_lsn,replay_lsn)/1024.0/1024)::numeric(10,1)                                                                               AS replay_mb
     , ((pg_wal_lsn_diff(CASE WHEN pg_is_in_recovery() THEN sent_lsn ELSE pg_current_wal_lsn() END,replay_lsn))::bigint/1024.0/1024)::numeric(10,1)     AS total_mb
     , replay_lag::interval(0) replay_lag
  FROM pg_stat_replication;

