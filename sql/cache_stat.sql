-- Show shared_buffers and os pagecache stat for current database
-- Require pg_buffercache and pgfincore
WITH qq AS (SELECT
  c.oid,
  count(b.bufferid) * 8192 AS size,
  (select sum(pages_mem) * 4096 from pgfincore(c.oid::regclass)) as size_in_pagecache
FROM pg_buffercache b
INNER JOIN pg_class c ON b.relfilenode = pg_relation_filenode(c.oid)
AND b.reldatabase IN (0, (SELECT oid FROM pg_database WHERE datname = current_database()))
GROUP BY 1)
SELECT
  pg_size_pretty(sum(qq.size)) AS shared_buffers_size,
  pg_size_pretty(sum(qq.size_in_pagecache)) AS size_in_pagecache,
  pg_size_pretty(pg_database_size(current_database())) as database_size
FROM qq;
