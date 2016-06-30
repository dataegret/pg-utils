SELECT 
  nspname,
  relname,
  relkind as "type",
  pg_size_pretty(pg_table_size(C.oid)) AS size,
  pg_size_pretty(pg_indexes_size(C.oid)) AS idxsize,
  pg_size_pretty(pg_total_relation_size(C.oid)) as "total"
FROM pg_class C
LEFT JOIN pg_namespace N ON (N.oid = C.relnamespace)
WHERE nspname NOT IN ('pg_catalog', 'information_schema') AND
  nspname !~ '^pg_toast' AND
  relkind IN ('r','i')
ORDER BY pg_total_relation_size(C.oid) DESC
LIMIT 20;