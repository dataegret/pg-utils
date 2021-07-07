WITH
buffer_data AS (
        SELECT
                relfilenode,
                pg_size_pretty(sum(case when isdirty then 1 else 0 end) * 8192) as dirty,
                round(100.0 * sum(case when isdirty then 1 else 0 end) / count(*), 1) as "dirty_%"
        FROM public.pg_buffercache GROUP BY 1
)

SELECT
	(n.nspname||'.'||c.relname)::varchar(30) AS "table",
	i.relname AS "index",
        coalesce(t.spcname, (select spcname from pg_tablespace where oid=(select dattablespace from pg_database where datname=current_database()))) AS tblsp,
	pg_size_pretty(pg_relation_size(i.oid)) AS size,
	pg_stat_get_blocks_fetched(i.oid) - pg_stat_get_blocks_hit(i.oid) AS disk,
	(100*(pg_stat_get_blocks_fetched(i.oid) - pg_stat_get_blocks_hit(i.oid))/GREATEST(1,pg_stat_get_blocks_fetched(i.oid)))::numeric(5,2) AS disk_rat,
        (pg_stat_get_blocks_fetched(i.oid) - pg_stat_get_blocks_hit(i.oid))/GREATEST(1,(pg_stat_get_tuples_inserted(c.oid)+(pg_stat_get_tuples_updated(c.oid)-pg_stat_get_tuples_hot_updated(c.oid))+pg_stat_get_tuples_deleted(c.oid))) AS d_w_rat,
        pg_stat_get_tuples_inserted(c.oid)+(pg_stat_get_tuples_updated(c.oid)-pg_stat_get_tuples_hot_updated(c.oid))+pg_stat_get_tuples_deleted(c.oid) AS write,
	pg_stat_get_numscans(i.oid) AS idx_scan,
--	pg_stat_get_tuples_returned(i.oid) AS idx_tup_read,
        buffer_data.dirty,
        buffer_data."%_dirty"
FROM pg_class c
	JOIN pg_index x ON c.oid = x.indrelid
	JOIN pg_class i ON i.oid = x.indexrelid
	LEFT JOIN buffer_data ON buffer_data.relfilenode = i.relfilenode
	LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
	LEFT JOIN pg_tablespace t ON t.oid=i.reltablespace
	LEFT JOIN pg_tablespace tr ON tr.oid=c.reltablespace
WHERE c.relkind = 'r'
AND (t.spcname IS DISTINCT FROM 'pg_global') and (n.nspname IS DISTINCT FROM 'pg_catalog')
AND pg_stat_get_blocks_fetched(i.oid) - pg_stat_get_blocks_hit(i.oid)>100
ORDER BY disk DESC NULLS LAST, idx_scan DESC LIMIT 50;



