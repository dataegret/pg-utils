--list single-column indexes which have only 5 or less distinct values in 95+% of rows with not null values.
--so they possibly may be replaced with partial indexes to save disk space.

SELECT
pg_index.indrelid::regclass AS table,
pg_attribute.attname AS column,
pg_index.indexrelid::regclass AS index,
pg_stats.null_frac,
pg_stats.most_common_freqs[1:5] AS most_common_freqs,
(pg_stats.most_common_vals::text::text[])[1:5] AS most_common_vals,
pg_size_pretty(pg_relation_size(pg_index.indexrelid)) AS index_size,
pg_get_indexdef(pg_index.indexrelid) AS index_def
FROM pg_index
JOIN pg_attribute ON pg_attribute.attrelid = pg_index.indrelid AND pg_attribute.attnum = ANY(pg_index.indkey)
JOIN pg_stats ON (pg_stats.schemaname || '.' || pg_stats.tablename)::regclass = pg_attribute.attrelid AND pg_stats.attname = pg_attribute.attname
WHERE pg_relation_size(pg_index.indexrelid) > 10*8192
AND (SELECT SUM(a) FROM unnest(most_common_freqs[1:5]) a) >= 0.95
AND array_length(pg_index.indkey, 1) = 1
ORDER BY pg_relation_size(pg_index.indexrelid) DESC,1,2,3;
