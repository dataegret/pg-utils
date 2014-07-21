

 select * from  (WITH totals_counts AS
(
        SELECT
                sum(pg_stat_get_blocks_fetched(c.oid)-pg_stat_get_blocks_hit(c.oid)+pg_stat_get_blocks_fetched(c.reltoastrelid)-pg_stat_get_blocks_hit(c.reltoastrelid)) as disk,
                sum(pg_stat_get_tuples_inserted(c.oid)+pg_stat_get_tuples_inserted(c.reltoastrelid)+2*(pg_stat_get_tuples_updated(c.oid)+pg_stat_get_tuples_updated(c.reltoastrelid))+pg_stat_get_tuples_deleted(c.oid)+pg_stat_get_tuples_deleted(c.reltoastrelid)) as write
        FROM pg_class c
        WHERE c.relkind='r'
)
SELECT
        (n.nspname||'.'||c.relname)::varchar(30),
        t.spcname AS tblsp,
        pg_size_pretty(pg_relation_size(c.oid)+(CASE WHEN c.reltoastrelid=0 THEN 0 ELSE pg_total_relation_size(c.reltoastrelid) END)) AS size,
        (pg_stat_get_blocks_fetched(c.oid)-pg_stat_get_blocks_hit(c.oid)+pg_stat_get_blocks_fetched(c.reltoastrelid)-pg_stat_get_blocks_hit(c.reltoastrelid))/GREATEST(1, (pg_stat_get_tuples_inserted(c.oid)+pg_stat_get_tuples_inserted(c.reltoastrelid)+2*(pg_stat_get_tuples_updated(c.oid)+pg_stat_get_tuples_updated(c.reltoastrelid))+pg_stat_get_tuples_deleted(c.oid)+pg_stat_get_tuples_deleted(c.reltoastrelid))) AS ratio,
        pg_stat_get_blocks_fetched(c.oid)-pg_stat_get_blocks_hit(c.oid)+pg_stat_get_blocks_fetched(c.reltoastrelid)-pg_stat_get_blocks_hit(c.reltoastrelid) AS disk,
        ((100*(pg_stat_get_blocks_fetched(c.oid)-pg_stat_get_blocks_hit(c.oid)+pg_stat_get_blocks_fetched(c.reltoastrelid)-pg_stat_get_blocks_hit(c.reltoastrelid)))/(SELECT disk FROM totals_counts))::numeric(5,2) AS "disk%",
        ((SELECT SUM(pg_stat_get_tuples_fetched(i.indexrelid))::bigint FROM pg_index i WHERE i.indrelid=c.oid) + pg_stat_get_tuples_fetched(c.oid))/GREATEST(1, (pg_stat_get_blocks_fetched(c.oid)-pg_stat_get_blocks_hit(c.oid)+pg_stat_get_blocks_fetched(c.reltoastrelid)-pg_stat_get_blocks_hit(c.reltoastrelid))) AS rt_d_rat,
        ((SELECT SUM(pg_stat_get_tuples_fetched(i.indexrelid))::bigint FROM pg_index i WHERE i.indrelid=c.oid) + pg_stat_get_tuples_fetched(c.oid)) AS r_tuples,
        pg_stat_get_tuples_inserted(c.oid)+pg_stat_get_tuples_inserted(c.reltoastrelid)+2*(pg_stat_get_tuples_updated(c.oid)+pg_stat_get_tuples_updated(c.reltoastrelid))+pg_stat_get_tuples_deleted(c.oid)+pg_stat_get_tuples_deleted(c.reltoastrelid) AS write,
        ((100*(pg_stat_get_tuples_inserted(c.oid)+pg_stat_get_tuples_inserted(c.reltoastrelid)+2*(pg_stat_get_tuples_updated(c.oid)+pg_stat_get_tuples_updated(c.reltoastrelid))+pg_stat_get_tuples_deleted(c.oid)+pg_stat_get_tuples_deleted(c.reltoastrelid)))/(SELECT write FROM totals_counts))::numeric(5,2) AS "write%",
        pg_stat_get_tuples_inserted(c.oid)+pg_stat_get_tuples_inserted(c.reltoastrelid) AS n_tup_ins,
        pg_stat_get_tuples_updated(c.oid)+pg_stat_get_tuples_updated(c.reltoastrelid) AS n_tup_upd,
        pg_stat_get_tuples_deleted(c.oid)+pg_stat_get_tuples_deleted(c.reltoastrelid) AS n_tup_del
FROM pg_class c
LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_tablespace t ON t.oid=c.reltablespace
WHERE 
	c.relkind='r'
	AND n.nspname IS DISTINCT FROM 'pg_catalog'
	AND t.spcname IS DISTINCT FROM 'ssd'
) as t1 
WHERE 
ratio>10
AND disk>1000
ORDER BY disk DESC NULLS LAST LIMIT 100;

