

CREATE OR REPLACE VIEW db_activity AS
    SELECT (now() - pg_stat_activity.xact_start) AS ts_age, pg_stat_activity.state, (now() - pg_stat_activity.query_start) as query_age, (now() - state_change) as change_age, pg_stat_activity.datname, pg_stat_activity.pid, pg_stat_activity.usename, pg_stat_activity.waiting, pg_stat_activity.client_addr, pg_stat_activity.client_port, pg_stat_activity.query 
FROM pg_stat_activity 
WHERE 
((now() - pg_stat_activity.xact_start) > '00:00:00.1'::interval)
-- OR ((now() - pg_stat_activity.query_start)> '00:00:00.5'::interval)
and pg_stat_activity.pid<>pg_backend_pid()
ORDER BY pg_stat_activity.xact_start;

