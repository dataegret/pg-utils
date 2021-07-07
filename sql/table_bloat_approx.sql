--faster version of table_bloat.sql which returns approximate results and doesn't read whole table (but reads toast tables)
--pgstattuple v1.3+ extension required (available since postgresql 9.5)
--WARNING: without table name/mask query will read all available tables which could cause I/O spikes
select nspname,
relname,
pg_size_pretty(relation_size + toast_relation_size) as total_size,
pg_size_pretty(toast_relation_size) as toast_size,
round(((relation_size - (relation_size - free_space)*100/fillfactor)*100/greatest(relation_size, 1))::numeric, 1) AS "table_waste_%",
pg_size_pretty((relation_size - (relation_size - free_space)*100/fillfactor)::bigint) table_waste,
round(((toast_free_space + relation_size - (relation_size - free_space)*100/fillfactor)*100/greatest(relation_size + toast_relation_size, 1))::numeric, 1) AS "total_waste_%",
pg_size_pretty((toast_free_space + relation_size - (relation_size - free_space)*100/fillfactor)::bigint) total_waste
from (
    select nspname, relname,
    (select approx_free_space from pgstattuple_approx(c.oid)) as free_space,
    pg_relation_size(c.oid) as relation_size,
    (case when reltoastrelid = 0 then 0 else (select free_space from pgstattuple(c.reltoastrelid)) end) as toast_free_space,
    coalesce(pg_relation_size(c.reltoastrelid), 0) as toast_relation_size,
    coalesce((SELECT (regexp_matches(reloptions::text, E'.*fillfactor=(\\d+).*'))[1]),'100')::real AS fillfactor
    from pg_class c
    left join pg_namespace n on (n.oid = c.relnamespace)
    where nspname not in ('pg_catalog', 'information_schema')
    and nspname !~ '^pg_toast' and nspname !~ '^pg_temp' and relkind in ('r', 'm') and (relpersistence = 'p' or not pg_is_in_recovery())
    --put your table name/mask here
    and relname ~ ''
) t
order by (toast_free_space + relation_size - (relation_size - free_space)*100/fillfactor) desc
limit 20;
