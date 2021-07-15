SELECT * FROM (
SELECT
	(n.nspname||'.'||c.relname)::varchar(40) AS "table",
	i.relname AS "index",
	t.spcname AS tblsp,
	pg_size_pretty(pg_relation_size(i.oid)) AS size,
	pg_stat_get_blocks_fetched(i.oid) - pg_stat_get_blocks_hit(i.oid) AS disk,
	(100*(pg_stat_get_blocks_fetched(i.oid) - pg_stat_get_blocks_hit(i.oid))/GREATEST(1,pg_stat_get_blocks_fetched(i.oid)))::numeric(5,2) AS disk_rat,
        (pg_stat_get_blocks_fetched(i.oid) - pg_stat_get_blocks_hit(i.oid))/GREATEST(1,(pg_stat_get_tuples_inserted(c.oid)+(pg_stat_get_tuples_updated(c.oid)-pg_stat_get_tuples_hot_updated(c.oid))+pg_stat_get_tuples_deleted(c.oid))) AS d_w_rat,
        pg_stat_get_tuples_inserted(c.oid)+(pg_stat_get_tuples_updated(c.oid)-pg_stat_get_tuples_hot_updated(c.oid))+pg_stat_get_tuples_deleted(c.oid) AS write,
	pg_stat_get_numscans(i.oid) AS idx_scan,
	pg_stat_get_tuples_returned(i.oid) AS idx_tup_read
FROM pg_class c
	JOIN pg_index x ON c.oid = x.indrelid
	JOIN pg_class i ON i.oid = x.indexrelid
	LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
	LEFT JOIN pg_tablespace t ON t.oid=i.reltablespace
	LEFT JOIN pg_tablespace tr ON tr.oid=c.reltablespace
WHERE c.relkind = 'r'
) AS t
WHERE d_w_rat<25
AND tblsp='ssd'
ORDER BY disk DESC NULLS LAST;
