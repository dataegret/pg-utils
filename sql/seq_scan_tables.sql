
SELECT
	schemaname||'.'||relname AS table,
	n_live_tup,
	seq_scan,
	seq_tup_read,
	(coalesce(n_tup_ins,0)+coalesce(n_tup_upd,0)+coalesce(n_tup_del,0)) as write_activity,
	(SELECT count(*) FROM pg_index WHERE pg_index.indrelid=pg_stat_all_tables.relid) AS index_count,
	idx_scan,
	idx_tup_fetch
FROM pg_stat_all_tables
WHERE
	seq_scan>0
	AND seq_tup_read>100000
	AND schemaname<>'pg_catalog'
ORDER BY
	seq_tup_read DESC
LIMIT 20;

