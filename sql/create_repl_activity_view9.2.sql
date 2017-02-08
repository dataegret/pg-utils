CREATE VIEW repl_activity AS SELECT
    client_addr AS client,
    usename AS user,
    application_name AS name,
    state, sync_state AS mode,
    (pg_xlog_location_diff(pg_current_xlog_location(),sent_location) / 1024)::bigint as pending,
    (pg_xlog_location_diff(sent_location,write_location) / 1024)::bigint as write,
    (pg_xlog_location_diff(write_location,flush_location) / 1024)::bigint as flush,
    (pg_xlog_location_diff(flush_location,replay_location) / 1024)::bigint as replay,
    (pg_xlog_location_diff(pg_current_xlog_location(),replay_location))::bigint / 1024 as total_lag
FROM pg_stat_replication;
