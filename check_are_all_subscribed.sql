
SELECT 'table' as type, n.nspname as schema, c.relname as name
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE   c.relkind = 'r'::"char"
AND n.nspname NOT LIKE 'pg_%' AND n.nspname<>'_slony' AND n.nspname<>'information_schema'
AND NOT EXISTS (select 1 from _slony.sl_table where tab_relname=c.relname and tab_nspname=n.nspname)

UNION ALL

SELECT 'sequence', n.nspname, c.relname
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE   c.relkind = 'S'::"char"
AND n.nspname NOT LIKE 'pg_%' AND n.nspname<>'_slony' AND n.nspname<>'information_schema'
AND NOT EXISTS (select 1 from _slony.sl_sequence where seq_relname=c.relname and seq_nspname=n.nspname)

order by 1,2,3;

