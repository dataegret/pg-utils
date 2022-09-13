--list reindex queries for btree indexes which could potentially benefit from postgresql 13 feature "btree index deduplication"
--duplicates_estimate represents estimated part with duplicates for each indexed column (including nulls) according to MCV list in statistics
--requires pageinspect extension to check if index already use deduplication

WITH selected_indexes AS materialized (
SELECT n.nspname AS schema_name,
  c.relname AS table_name,
  i.relname AS index_name,
  pg_relation_size(x.indexrelid) AS index_size_bytes,
  pg_relation_size(c.oid) AS table_size_bytes,
  replace(pg_get_indexdef(i.oid), 'CREATE INDEX ', '') AS index_def,
  (SELECT array_agg(round(f::numeric,4)) FROM
  (
    (SELECT max(null_frac) + (1 - max(null_frac))*coalesce(SUM(u), 0) AS f FROM pg_attribute a JOIN pg_stats s ON (s.schemaname = n.nspname AND s.tablename = c.relname AND s.attname = a.attname) LEFT JOIN LATERAL unnest(s.most_common_freqs) u ON TRUE WHERE a.attrelid = x.indrelid AND a.attnum = ANY(x.indkey) GROUP BY a.attnum ORDER BY array_position(x.indkey, a.attnum))
    UNION ALL 
    (SELECT max(null_frac) + (1 - max(null_frac))*coalesce(SUM(u2), 0) AS f FROM pg_stats s2 LEFT JOIN LATERAL unnest(s2.most_common_freqs) u2 ON true WHERE s2.schemaname = n.nspname AND s2.tablename = i.relname GROUP BY s2.attname)
  ) t
  ) AS sum_most_common_freqs
 FROM pg_index x
   JOIN pg_class c ON c.oid = x.indrelid
   JOIN pg_class i ON i.oid = x.indexrelid
   LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
   JOIN pg_am am ON am.oid = i.relam AND am.amname = 'btree'--only btree indexes
WHERE
c.relkind IN ('r', 'm') AND i.relkind = 'i'--skip partitioned indexes
AND (c.relpersistence = 'p' or not pg_is_in_recovery())--skip unlogged indexes
AND x.indisunique = 'f'--skip unique indexes
AND x.indisvalid = 't'
AND pg_relation_size(x.indexrelid) > 1024*1024--skip indexes smaller than 1MB
AND n.nspname != 'pg_catalog'
)
SELECT
format('-- index size: %s, table size: %s, duplicates_estimate: %s
-- %s
reindex index concurrently %s;
',
pg_size_pretty(index_size_bytes), pg_size_pretty(table_size_bytes), sum_most_common_freqs, index_def, (case when schema_name = 'public' then format('%I', index_name) else format('%I.%I', schema_name, index_name) end)) as reindex_queries

FROM selected_indexes WHERE
(bt_metap(format('%I.%I', schema_name, index_name))).allequalimage = 'f'--skip indexes already in new format
AND 0.05 <= ALL(sum_most_common_freqs)--require at least 5% of duplicates on each indexed column
ORDER BY index_size_bytes DESC;