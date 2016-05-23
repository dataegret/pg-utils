
SELECT
        CASE c.relkind
                WHEN 'r' THEN
                        'GRANT SELECT ON TABLE "'||n.nspname||'"."'||c.relname||'" TO role_ro;'
                WHEN 'v' THEN
                        'GRANT SELECT ON TABLE "'||n.nspname||'"."'||c.relname||'" TO role_ro;'
                WHEN 'm' THEN
                        'GRANT SELECT ON TABLE "'||n.nspname||'"."'||c.relname||'" TO role_ro;'
                WHEN 'S' THEN
                        'GRANT SELECT ON SEQUENCE "'||n.nspname||'"."'||c.relname||'" TO role_ro;'
        END as "NEW GRANT"
FROM pg_catalog.pg_class c
LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE
        c.relkind IN ('r', 'v', 'm', 'S')
        AND n.nspname !~ '^pg_'
        AND n.nspname not in ('information_schema', '_slony')
AND (
        c.relacl IS NULL
        OR c.relacl::text not like '%role_ro=r/%'
        OR CASE c.relkind
        WHEN 'r' THEN c.relacl::text not like '%role_rw=arwd/%'
        WHEN 'v' THEN c.relacl::text not like '%role_rw=r/%'
        WHEN 'm' THEN c.relacl::text not like '%role_rw=r/%'
        WHEN 'S' THEN c.relacl::text not like '%role_rw=rU/%'
        END
)
UNION ALL
SELECT
        CASE c.relkind
                WHEN 'r' THEN
                        'GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "'||n.nspname||'"."'||c.relname||'" TO role_rw;'
                WHEN 'v' THEN
                        'GRANT SELECT ON TABLE "'||n.nspname||'"."'||c.relname||'" TO role_rw;'
                WHEN 'm' THEN
                        'GRANT SELECT ON TABLE "'||n.nspname||'"."'||c.relname||'" TO role_rw;'
                WHEN 'S' THEN
                        'GRANT SELECT,USAGE ON SEQUENCE "'||n.nspname||'"."'||c.relname||'" TO role_rw;'
        END as "NEW GRANT"
FROM pg_catalog.pg_class c
LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE
        c.relkind IN ('r', 'v', 'm', 'S')
        AND n.nspname !~ '^pg_'
        AND n.nspname not in ('information_schema', '_slony')
AND (
        c.relacl IS NULL
        OR c.relacl::text not like '%role_ro=r/%'
        OR CASE c.relkind
        WHEN 'r' THEN c.relacl::text not like '%role_rw=arwd/%'
        WHEN 'v' THEN c.relacl::text not like '%role_rw=r/%'
        WHEN 'm' THEN c.relacl::text not like '%role_rw=r/%'
        WHEN 'S' THEN c.relacl::text not like '%role_rw=rU/%'
        END
)
ORDER BY 1

