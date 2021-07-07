
SELECT
pg_stat_all_tables.schemaname||'.'||pg_stat_all_tables.relname AS table,
pg_size_pretty(pg_relation_size(relid)) AS size,
coalesce(t.spcname, (select spcname from pg_tablespace where oid=(select dattablespace from pg_database where datname=current_database()))) AS tblsp,
seq_scan,
idx_scan,
n_tup_ins,
n_tup_upd,
n_tup_del,
coalesce(n_tup_ins,0)+2*coalesce(n_tup_upd,0)-coalesce(n_tup_hot_upd,0)+coalesce(n_tup_del,0) as total,
(coalesce(n_tup_hot_upd,0)::float*100/(case when n_tup_upd>0 then n_tup_upd else 1 end)::float)::numeric(10,2) as HOT_rate,
(select v[1] FROM regexp_matches(reloptions::text,E'fillfactor=(\\d+)') as r(v) limit 1) as fillfactor
from pg_stat_all_tables
JOIN pg_class c ON c.oid=relid
LEFT JOIN pg_tablespace t ON t.oid=c.reltablespace
WHERE
(coalesce(n_tup_ins,0)+coalesce(n_tup_upd,0)+coalesce(n_tup_del,0))>0
and pg_stat_all_tables.schemaname not in ('pg_catalog', 'pg_global')
order by total desc limit 50;

