--usage: psql -t -c "select datname from pg_database where datname not in ('template0', 'template1') order by pg_database_size(datname)" | xargs -I {} sh -c 'echo {}; psql -d {} -f ~/stuff/sql/amcheck_indexes.sql'

\set ECHO errors
\set QUIET on
\timing off
\pset format unaligned
\pset recordsep_zero
\t on
set client_min_messages to warning;
CREATE EXTENSION IF NOT EXISTS amcheck;
SELECT format($$ SELECT bt_index_check(%L,true /* %s */);$$, indexrelid::regclass, pg_relation_size(indexrelid))
FROM (
	SELECT DISTINCT indexrelid, indrelid, indcollation[i] coll, pg_index.indclass[0] as op FROM pg_index, generate_subscripts(indcollation, 1) g(i)
	 --WHERE 
 --NOT (indisunique OR indisprimary)
 --NOT indisprimary AND indisunique
 --indisprimary
) s 
  JOIN pg_collation c ON coll=c.oid
  JOIN pg_opclass op ON op.oid=s.op JOIN pg_am am ON am.oid=op.opcmethod AND am.amname='btree'
WHERE collprovider IN ('d', 'c') AND collname NOT IN ('C', 'POSIX')
ORDER BY pg_relation_size(indexrelid) \gexec

