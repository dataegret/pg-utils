SELECT (clock_timestamp() - pg_stat_activity.xact_start) AS ts_age, pg_stat_activity.state, (clock_timestamp() - pg_stat_activity.query_start) as query_age, (clock_timestamp() - state_change) as change_age, pg_stat_activity.datname, pg_stat_activity.pid, pg_stat_activity.usename, pg_stat_activity.waiting, pg_stat_activity.client_addr, pg_stat_activity.client_port, pg_stat_activity.query
FROM pg_stat_activity
WHERE
((clock_timestamp() - pg_stat_activity.xact_start > '00:00:00.1'::interval) OR (clock_timestamp() - pg_stat_activity.query_start > '00:00:00.1'::interval and state = 'idle in transaction (aborted)'))
and pg_stat_activity.pid<>pg_backend_pid()
ORDER BY coalesce(pg_stat_activity.xact_start, pg_stat_activity.query_start);