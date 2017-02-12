CREATE VIEW repl_activity AS SELECT
    client_addr AS client,
    usename AS user,
    application_name AS name,
    state, sync_state AS mode,
    (pg_xlog_location_diff(pg_current_xlog_location(),sent_location) / 1024)::bigint as pending,
    (pg_xlog_location_diff(sent_location,write_location) / 1024)::bigint as write,
    (pg_xlog_location_diff(write_location,flush_location) / 1024)::bigint as flush,
    (pg_xlog_location_diff(flush_location,replay_location) / 1024)::bigint as replay,
    (pg_xlog_location_diff(pg_current_xlog_location(),replay_location))::bigint / 1024 as total_lag,
    (pg_last_committed_xact()).xid::text::bigint - backend_xmin::text::bigint as xact_age,
    (pg_last_committed_xact()).timestamp - pg_xact_commit_timestamp(backend_xmin) as time_age
FROM pg_stat_replication;
