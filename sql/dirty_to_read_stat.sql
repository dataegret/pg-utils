WITH
buffer_data AS (
        SELECT
                relfilenode,
                sum(case when isdirty then 1 else 0 end) as dirty_pages,
                round(100.0 * sum(case when isdirty then 1 else 0 end) / count(*), 1) as "dirty_%",
		count(*) as cached_pages
        FROM public.pg_buffercache GROUP BY 1
)

SELECT
        n.nspname||'.'||c.relname as relation,
	c.relkind,
        t.spcname AS tblsp,
        pg_size_pretty(pg_relation_size(c.oid)) AS relsize,
	round(buffer_data.cached_pages::numeric*100*8192/pg_relation_size(c.oid), 1) as "cached_%",
        pg_size_pretty(8192*(pg_stat_get_blocks_fetched(c.oid)-pg_stat_get_blocks_hit(c.oid)+pg_stat_get_blocks_fetched(c.reltoastrelid)-pg_stat_get_blocks_hit(c.reltoastrelid))) AS disk_read,
        pg_size_pretty(buffer_data.dirty_pages*8192) as dirty_size,
        buffer_data."dirty_%",
	round((pg_stat_get_blocks_fetched(c.oid)-pg_stat_get_blocks_hit(c.oid)+pg_stat_get_blocks_fetched(c.reltoastrelid)-pg_stat_get_blocks_hit(c.reltoastrelid))::numeric/buffer_data.dirty_pages, 1) as read_to_dirty_ratio
FROM pg_class c
LEFT JOIN buffer_data ON buffer_data.relfilenode = c.relfilenode
LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_tablespace t ON t.oid=c.reltablespace
WHERE
dirty_pages>0
ORDER BY dirty_pages desc LIMIT 60;