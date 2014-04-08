
select pc1.oid::regclass||'.'||pa1.attname, pt1.typname, pc2.relname||'.'||pa2.attname, pt2.typname from pg_constraint pco join pg_class pc1 on pc1.oid=conrelid join pg_class pc2 on pc2.oid=confrelid join pg_attribute pa1 on pa1.attnum=conkey[1] and pa1.attrelid=conrelid join pg_attribute pa2 on pa2.attnum=confkey[1] and pa2.attrelid=confrelid join pg_type pt1 on pt1.oid=pa1.atttypid join pg_type pt2 on pt2.oid=pa2.atttypid where pa1.atttypid<>pa2.atttypid and contype='f' order by 1,2;

