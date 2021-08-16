\prompt 'This utility will read indexes with given mask using pgstattuple extension and return top 100 bloated indexes.\nWARNING: without index mask query will read all available indexes which could cause I/O spikes.\nPlease enter mask for index name (check all indexes if nothing is specified): ' indexname

with indexes as (
    select * from pg_stat_user_indexes
)
select table_name,
pg_size_pretty(table_size) as table_size,
index_name,
pg_size_pretty(index_size) as index_size,
idx_scan as index_scans,
round((free_space*100/index_size)::numeric, 1) as waste_percent,
pg_size_pretty(free_space) as waste
from (
    select (case when schemaname = 'public' then format('%I', p.relname) else format('%I.%I', schemaname, p.relname) end) as table_name,
    indexrelname as index_name,
    (select (case when avg_leaf_density = 'NaN' then 0
        else greatest(ceil(index_size * (1 - avg_leaf_density / (coalesce((SELECT (regexp_matches(reloptions::text, E'.*fillfactor=(\\d+).*'))[1]),'90')::real)))::bigint, 0) end)
        from pgstatindex(p.indexrelid::regclass::text)
    ) as free_space,
    pg_relation_size(p.indexrelid) as index_size,
    pg_relation_size(p.relid) as table_size,
    idx_scan
    from indexes p
    join pg_class c on p.indexrelid = c.oid
    join pg_index i on i.indexrelid = p.indexrelid
    where pg_get_indexdef(p.indexrelid) like '%USING btree%' and
    i.indisvalid and (c.relpersistence = 'p' or not pg_is_in_recovery()) and
    --put your index name/mask here
    indexrelname ~ :'indexname'
) t
order by free_space desc
limit 100;