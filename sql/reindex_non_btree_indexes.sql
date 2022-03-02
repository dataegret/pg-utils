--list reindex concurrently queries for non btree indexes larger than 1MB (largest first)
--PostgreSQL 12+ required

SELECT
format('-- index size: %s, table size: %s
-- %s
reindex index concurrently %s;
',
pg_size_pretty(pg_relation_size(x.indexrelid)), pg_size_pretty(pg_relation_size(x.indrelid)),  replace(pg_get_indexdef(i.oid), 'CREATE INDEX ', ''), (case when n.nspname = 'public' then format('%I', i.relname) else format('%I.%I', n.nspname, i.relname) end)) as reindex_queries
FROM pg_index x
   JOIN pg_class c ON c.oid = x.indrelid
   JOIN pg_class i ON i.oid = x.indexrelid
   LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
   JOIN pg_am am ON am.oid = i.relam AND am.amname != 'btree'
WHERE
   c.relkind IN ('r', 'm') AND i.relkind = 'i'--skip partitioned indexes
   AND pg_relation_size(x.indexrelid) > 1024*1024--skip indexes smaller than 1MB
ORDER BY pg_relation_size(x.indexrelid) desc;