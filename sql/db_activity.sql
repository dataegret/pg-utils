
SELECT (now() - pg_stat_activity.xact_start) AS age, pg_stat_activity.datname, pg_stat_activity.procpid, pg_stat_activity.usename, pg_stat_activity.waiting, pg_stat_activity.query_start, pg_stat_activity.client_addr, pg_stat_activity.client_port, pg_stat_activity.current_query FROM pg_stat_activity WHERE ((pg_stat_activity.xact_start IS NOT NULL) AND ((now() - pg_stat_activity.xact_start) > '00:00:00.5'::interval)) and pg_stat_activity.procpid<>pg_backend_pid() ORDER BY pg_stat_activity.xact_start;

