SELECT
    n.nspname AS schema,
    c.relname AS relname
FROM pg_catalog.pg_class c
LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE
    c.relkind = 'r'::"char"
    AND n.nspname NOT LIKE 'pg_%' AND n.nspname<>'_slony' AND n.nspname<>'information_schema'
    AND NOT EXISTS (
        SELECT
        FROM pg_catalog.pg_constraint
        WHERE
            pg_catalog.pg_constraint.contype='p'
            AND pg_catalog.pg_constraint.conrelid=c.oid
         )
ORDER BY 1,2

