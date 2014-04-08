BEGIN;

CREATE TEMP SEQUENCE tab_seq;
CREATE TEMP SEQUENCE seq_seq;

SELECT 'SET ADD TABLE (set id=@main, origin=@master, id='||nextval('tab_seq')||', fully qualified name = '''||fullname||''''||(case when have_pk then ');' else ', key='''||uniq_index||''');' end)
	FROM (
	SELECT
		n.nspname||'.'||c.relname AS fullname,
		(SELECT exists (SELECT indexrelid from pg_catalog.pg_index WHERE indisprimary is true AND indisvalid is true AND indrelid=c.oid)) AS have_pk,
		(SELECT c1.relname from pg_catalog.pg_index i
		JOIN pg_catalog.pg_class c1 ON c1.oid=i.indexrelid 
		WHERE
			i.indisprimary is false AND
			i.indisunique is true AND
			i.indisvalid is true
			AND i.indrelid=c.oid
			AND NOT EXISTS (
				SELECT i_attr.attname
				FROM pg_catalog.pg_attribute t_attr
				JOIN pg_catalog.pg_attribute i_attr ON i_attr.attname=t_attr.attname AND i_attr.attrelid = i.indexrelid
				WHERE t_attr.attrelid = c.oid AND t_attr.attnotnull <> 't'
		 	)
		 ORDER BY 1 LIMIT 1) AS uniq_index
	FROM pg_catalog.pg_class c
	JOIN pg_namespace n ON n.oid = c.relnamespace
	WHERE	 c.relkind = 'r'::"char"
		AND n.nspname NOT LIKE 'pg_%' AND n.nspname<>'_slony' AND n.nspname<>'information_schema'
	ORDER BY have_pk desc, fullname
	) AS t1
WHERE (have_pk IS TRUE OR uniq_index IS NOT NULL)

UNION ALL

SELECT 'SET ADD SEQUENCE (set id=@main, origin=@master, id='||nextval('seq_seq')||', fully qualified name = '''||fullname||''');'
	FROM (
	SELECT
		n.nspname||'.'||c.relname AS fullname
	FROM pg_catalog.pg_class c
	JOIN pg_namespace n ON n.oid = c.relnamespace
	WHERE	 c.relkind = 'S'::"char"
		AND n.nspname NOT LIKE 'pg_%' AND n.nspname<>'_slony' AND n.nspname<>'information_schema'
	ORDER BY fullname
	) AS t1;

COMMIT;

