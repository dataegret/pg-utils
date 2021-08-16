\prompt 'This utility will read tables with given mask using pgstattuple extension and return top 20 bloated tables.\nWARNING: without table mask query will read all available tables which could cause I/O spikes.\nPlease enter mask for table name (check all tables if nothing is specified): ' tablename
--pgstattuple extension required
--WARNING: without table name/mask query will read all available tables which could cause I/O spikes
select table_name,
pg_size_pretty(relation_size + toast_relation_size) as total_size,
pg_size_pretty(toast_relation_size) as toast_size,
round(((relation_size - (relation_size - free_space)*100/fillfactor)*100/greatest(relation_size, 1))::numeric, 1) table_waste_percent,
pg_size_pretty((relation_size - (relation_size - free_space)*100/fillfactor)::bigint) table_waste,
round(((toast_free_space + relation_size - (relation_size - free_space)*100/fillfactor)*100/greatest(relation_size + toast_relation_size, 1))::numeric, 1) total_waste_percent,
pg_size_pretty((toast_free_space + relation_size - (relation_size - free_space)*100/fillfactor)::bigint) total_waste
from (
    select
    (case when n.nspname = 'public' then format('%I', c.relname) else format('%I.%I', n.nspname, c.relname) end) as table_name,
    (select free_space from pgstattuple(c.oid)) as free_space,
    pg_relation_size(c.oid) as relation_size,
    (case when reltoastrelid = 0 then 0 else (select free_space from pgstattuple(c.reltoastrelid)) end) as toast_free_space,
    coalesce(pg_relation_size(c.reltoastrelid), 0) as toast_relation_size,
    coalesce((SELECT (regexp_matches(reloptions::text, E'.*fillfactor=(\\d+).*'))[1]),'100')::real AS fillfactor
    from pg_class c
    left join pg_namespace n on (n.oid = c.relnamespace)
    where nspname not in ('pg_catalog', 'information_schema')
    and nspname !~ '^pg_toast' and nspname !~ '^pg_temp' and relkind in ('r', 'm') and (relpersistence = 'p' or not pg_is_in_recovery())
    --put your table name/mask here
    and relname ~ :'tablename'
) t
order by (toast_free_space + relation_size - (relation_size - free_space)*100/fillfactor) desc
limit 20;