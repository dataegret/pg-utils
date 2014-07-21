                SELECT
                        n.nspname AS schema,
                        c.relname AS relname
                FROM pg_catalog.pg_class c
                LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
                WHERE
                        c.relkind = 'r'::"char"
                        AND
			n.nspname NOT LIKE 'pg_%' AND n.nspname<>'_slony' AND n.nspname<>'information_schema'
                        AND
                        NOT EXISTS (
                                SELECT
                                        pg_catalog.pg_index.indexrelid
                                FROM pg_catalog.pg_index
                                WHERE
                                        pg_catalog.pg_index.indrelid=c.oid
                                AND
                                        pg_catalog.pg_index.indisunique='t'
                                AND
                                NOT EXISTS (
                                        SELECT
                                                i_attr.attname
                                        FROM pg_catalog.pg_attribute t_attr
                                        JOIN pg_catalog.pg_attribute i_attr ON i_attr.attname=t_attr.attname AND i_attr.attrelid = pg_catalog.pg_index.indexrelid
                                        WHERE
                                                t_attr.attrelid = c.oid
                                                AND
                                                t_attr.attnotnull <> 't'
                                )
                        )
                ORDER BY 1,2

