WITH index_data AS (
         SELECT idx.*,
                string_to_array(idx.indkey::text, ' ')                  as key_array,
                array_length(string_to_array(idx.indkey::text, ' '), 1) as nkeys,
                am.amname
         FROM pg_index AS idx
         JOIN pg_class AS cls ON cls.oid = idx.indexrelid
         JOIN pg_am am ON am.oid = cls.relam
         ),
     t AS (
         SELECT
             i1.indrelid::regclass::text as table_name,
             pg_get_indexdef(i1.indexrelid)                  main_index,
             pg_get_indexdef(i2.indexrelid)                  redundant_index,
             pg_size_pretty(pg_relation_size(i2.indexrelid)) redundant_index_size
         FROM index_data as i1
         JOIN index_data as i2 ON i1.indrelid = i2.indrelid
             AND i1.indexrelid <> i2.indexrelid
             AND i1.amname = i2.amname
         WHERE (regexp_replace(i1.indpred, 'location \d+', 'location', 'g') IS NOT DISTINCT FROM
                regexp_replace(i2.indpred, 'location \d+', 'location', 'g'))
           AND (regexp_replace(i1.indexprs, 'location \d+', 'location', 'g') IS NOT DISTINCT FROM
                regexp_replace(i2.indexprs, 'location \d+', 'location', 'g'))
           AND ((i1.nkeys > i2.nkeys and not i2.indisunique) OR (i1.nkeys = i2.nkeys and
                                                                 ((i1.indisunique and i2.indisunique and (i1.indexrelid > i2.indexrelid)) or
                                                                  (not i1.indisunique and not i2.indisunique and
                                                                   (i1.indexrelid > i2.indexrelid)) or
                                                                  (i1.indisunique and not i2.indisunique))))
           AND i1.key_array[1:i2.nkeys] = i2.key_array
         ORDER BY pg_relation_size(i2.indexrelid) desc,
                  i1.indexrelid::regclass::text,
                  i2.indexrelid::regclass::text
     )
SELECT DISTINCT ON (redundant_index) * FROM t;
