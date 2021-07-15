select
pg_index.indrelid::regclass as table,
pg_index.indexrelid::regclass as index,
pg_attribute.attname as field,
pg_statistic.stanullfrac,
pg_size_pretty(pg_relation_size(pg_index.indexrelid)) as indexsize,
pg_get_indexdef(pg_index.indexrelid) as indexdef
from pg_index
join pg_attribute ON pg_attribute.attrelid=pg_index.indrelid AND pg_attribute.attnum=ANY(pg_index.indkey)
join pg_statistic ON pg_statistic.starelid=pg_index.indrelid AND pg_statistic.staattnum=pg_attribute.attnum
where pg_statistic.stanullfrac>0.5 AND pg_relation_size(pg_index.indexrelid)>10*8192
order by pg_relation_size(pg_index.indexrelid) desc,1,2,3;


