
WITH totals_counts AS
(
        SELECT
                greatest(1, sum(pg_stat_get_blocks_fetched(c.oid)-pg_stat_get_blocks_hit(c.oid)+pg_stat_get_blocks_fetched(c.reltoastrelid)-pg_stat_get_blocks_hit(c.reltoastrelid))) as disk,
                greatest(1, sum(pg_stat_get_tuples_inserted(c.oid)+pg_stat_get_tuples_inserted(c.reltoastrelid)+2*(pg_stat_get_tuples_updated(c.oid)+pg_stat_get_tuples_updated(c.reltoastrelid))+pg_stat_get_tuples_deleted(c.oid)+pg_stat_get_tuples_deleted(c.reltoastrelid))) as write
        FROM pg_class c
        LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relkind='r'
        AND n.nspname IS DISTINCT FROM 'pg_catalog'
),
buffer_data AS (
        SELECT
                relfilenode,
                pg_size_pretty(sum(case when isdirty then 1 else 0 end) * 8192) as dirty,
                round(100.0 * sum(case when isdirty then 1 else 0 end) / count(*), 1) as "%_dirty"
        FROM public.pg_buffercache GROUP BY 1
)

SELECT
        (n.nspname||'.'||c.relname),
        coalesce(t.spcname, (select spcname from pg_tablespace where oid=(select dattablespace from pg_database where datname=current_database()))) AS tblsp,
        pg_size_pretty(pg_relation_size(c.oid)+(CASE WHEN c.reltoastrelid=0 THEN 0 ELSE pg_total_relation_size(c.reltoastrelid) END)) AS size,
        (pg_stat_get_blocks_fetched(c.oid)-pg_stat_get_blocks_hit(c.oid)+pg_stat_get_blocks_fetched(c.reltoastrelid)-pg_stat_get_blocks_hit(c.reltoastrelid))/GREATEST(1, (pg_stat_get_tuples_inserted(c.oid)+pg_stat_get_tuples_inserted(c.reltoastrelid)+2*(pg_stat_get_tuples_updated(c.oid)+pg_stat_get_tuples_updated(c.reltoastrelid))+pg_stat_get_tuples_deleted(c.oid)+pg_stat_get_tuples_deleted(c.reltoastrelid))) AS ratio,
        pg_stat_get_blocks_fetched(c.oid)-pg_stat_get_blocks_hit(c.oid)+pg_stat_get_blocks_fetched(c.reltoastrelid)-pg_stat_get_blocks_hit(c.reltoastrelid) AS disk,
        ((100*(pg_stat_get_blocks_fetched(c.oid)-pg_stat_get_blocks_hit(c.oid)+pg_stat_get_blocks_fetched(c.reltoastrelid)-pg_stat_get_blocks_hit(c.reltoastrelid)))/(SELECT disk FROM totals_counts))::numeric(5,2) AS "disk%",
        ((SELECT SUM(pg_stat_get_tuples_fetched(i.indexrelid))::bigint FROM pg_index i WHERE i.indrelid=c.oid) + pg_stat_get_tuples_fetched(c.oid))/GREATEST(1, (pg_stat_get_blocks_fetched(c.oid)-pg_stat_get_blocks_hit(c.oid)+pg_stat_get_blocks_fetched(c.reltoastrelid)-pg_stat_get_blocks_hit(c.reltoastrelid))) AS rt_d_rat,
        ((SELECT SUM(pg_stat_get_tuples_fetched(i.indexrelid))::bigint FROM pg_index i WHERE i.indrelid=c.oid) + pg_stat_get_tuples_fetched(c.oid)) AS r_tuples,
        pg_stat_get_tuples_inserted(c.oid)+pg_stat_get_tuples_inserted(c.reltoastrelid)+2*(pg_stat_get_tuples_updated(c.oid)+pg_stat_get_tuples_updated(c.reltoastrelid))+pg_stat_get_tuples_deleted(c.oid)+pg_stat_get_tuples_deleted(c.reltoastrelid) AS write,
        ((100*(pg_stat_get_tuples_inserted(c.oid)+pg_stat_get_tuples_inserted(c.reltoastrelid)+2*(pg_stat_get_tuples_updated(c.oid)+pg_stat_get_tuples_updated(c.reltoastrelid))+pg_stat_get_tuples_deleted(c.oid)+pg_stat_get_tuples_deleted(c.reltoastrelid)))/(SELECT write FROM totals_counts))::numeric(5,2) AS "write%",
        buffer_data.dirty,
        buffer_data."%_dirty"
FROM pg_class c
LEFT JOIN buffer_data ON buffer_data.relfilenode = c.relfilenode
LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_tablespace t ON t.oid=c.reltablespace
WHERE
c.relkind='r'
AND n.nspname IS DISTINCT FROM 'pg_catalog'
AND (
        pg_stat_get_tuples_fetched(c.oid)>100
        OR
        pg_stat_get_tuples_inserted(c.oid)+pg_stat_get_tuples_inserted(c.reltoastrelid)+2*(pg_stat_get_tuples_updated(c.oid)+pg_stat_get_tuples_updated(c.reltoastrelid))+pg_stat_get_tuples_deleted(c.oid)+pg_stat_get_tuples_deleted(c.reltoastrelid)>10
)
ORDER BY disk DESC NULLS LAST, r_tuples desc, size desc LIMIT 50;

