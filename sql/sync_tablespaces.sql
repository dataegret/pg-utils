

SELECT 'ALTER INDEX '||pg_indexes.schemaname||'."'||pg_indexes.indexname||'" SET TABLESPACE '||coalesce(pg_tables.tablespace,'pg_default')||';' from pg_indexes,pg_tables where pg_indexes.schemaname=pg_tables.schemaname and pg_indexes.tablename=pg_tables.tablename and pg_tables.tablespace IS DISTINCT FROM pg_indexes.tablespace order by pg_total_relation_size(pg_indexes.schemaname||'.'||'"'||pg_indexes.indexname||'"') desc;
