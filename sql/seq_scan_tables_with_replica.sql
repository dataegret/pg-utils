
SELECT
	local.schemaname||'.'||local.relname,
	local.n_live_tup,
	local.seq_scan AS local_seq_scan,
	remote.seq_scan AS remote_seq_scan,
	local.seq_tup_read AS local_seq_tup_read,
	remote.seq_tup_read AS remote_seq_tup_read,
	(coalesce(local.n_tup_ins,0)+coalesce(local.n_tup_upd,0)+coalesce(local.n_tup_del,0)) AS write_activity,
	(SELECT count(*) FROM pg_index WHERE pg_index.indrelid=relid) AS index_count
FROM pg_stat_all_tables AS local
join replica_fdw.pg_stat_all_tables AS remote USING (relid)
WHERE
	(local.seq_scan+remote.seq_scan)>0
	AND (local.seq_tup_read+remote.seq_tup_read)>100000
	AND local.schemaname<>'pg_catalog'
ORDER BY
	local.seq_tup_read+remote.seq_tup_read DESC
LIMIT 20;

