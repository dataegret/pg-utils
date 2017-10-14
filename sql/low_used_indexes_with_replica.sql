
SELECT
        local.schemaname||'.'||local.relname,
        local.indexrelname,
        local.idx_scan as local_used,
	replica.idx_scan as remote_used,
        (coalesce(n_tup_ins,0)+coalesce(n_tup_upd,0)-coalesce(n_tup_hot_upd,0)+coalesce(n_tup_del,0)) as write_activity,
        pg_stat_user_tables.seq_scan,
        pg_stat_user_tables.n_live_tup,
	pg_size_pretty(pg_relation_size(indexrelid::regclass)) as size
from pg_stat_user_indexes as local
join replica_fdw.pg_stat_user_indexes as replica USING (relid, indexrelid)
join pg_stat_user_tables USING (relid)
join pg_index USING (indexrelid)
where
        pg_index.indisunique is false
        and 
	--heuristic between table size, index usage and write actibity)
	(local.idx_scan+replica.idx_scan)::float*pg_relation_size(relid::regclass)<=10*(coalesce(n_tup_ins,0)+coalesce(n_tup_upd,0)-coalesce(n_tup_hot_upd,0)+coalesce(n_tup_del,0))::float
	--skip small unused indexes on zero write tables
	and not ((coalesce(n_tup_ins,0)+coalesce(n_tup_upd,0)-coalesce(n_tup_hot_upd,0)+coalesce(n_tup_del,0))<100000 and pg_relation_size(indexrelid::regclass)<100*1024*1024)
order by write_activity desc,pg_relation_size(relid::regclass) desc, local.indexrelname

