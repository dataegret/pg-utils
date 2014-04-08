SELECT  
	CASE c.relkind WHEN 'r' THEN 'table' WHEN 'v' THEN 'view' WHEN 'S' THEN 'sequence' END as "Type", 
	n.nspname||'.'||c.relname as "Name",
	c.relacl as "Access privileges" 
FROM pg_catalog.pg_class c 
LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace 
WHERE 
c.relkind IN ('r', 'v', 'S') 
AND n.nspname !~ '^pg_' 
AND n.nspname not in ('information_schema', '_slony', 'tables_to_drop') 
AND (
	c.relacl IS NULL 
	OR c.relacl::text not like '%role_ro=r/%'
	OR CASE c.relkind 
	WHEN 'r' THEN c.relacl::text not like '%role_rw=arwd/%'
	WHEN 'v' THEN c.relacl::text not like '%role_rw=r/%'
	WHEN 'S' THEN c.relacl::text not like '%role_rw=rU/%'
	END
) 
ORDER BY 1, 2;

