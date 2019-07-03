
SELECT pg_stat_user_indexes.schemaname || '.' || pg_stat_user_indexes.relname tablemane
     , pg_stat_user_indexes.indexrelname
     , pg_stat_user_indexes.idx_scan
     , psut.write_activity
     , psut.seq_scan
     , psut.n_live_tup
     , pg_size_pretty (pg_relation_size (pg_index.indexrelid::regclass)) as size

  from pg_stat_user_indexes
  join pg_index
    ON pg_stat_user_indexes.indexrelid = pg_index.indexrelid

  join (select pg_stat_user_tables.relid
             , pg_stat_user_tables.seq_scan
             , pg_stat_user_tables.n_live_tup
             , ( coalesce (pg_stat_user_tables.n_tup_ins, 0)
               + coalesce (pg_stat_user_tables.n_tup_upd, 0)
               - coalesce (pg_stat_user_tables.n_tup_hot_upd, 0)
               + coalesce (pg_stat_user_tables.n_tup_del, 0)
               ) as write_activity
          from pg_stat_user_tables) psut
    on pg_stat_user_indexes.relid = psut.relid

 where pg_index.indisunique is false
   and pg_stat_user_indexes.idx_scan::float / (psut.write_activity + 1)::float < 0.01
   and psut.write_activity > case when pg_is_in_recovery () then -1 else 10000 end
  order by 4 desc, 1, 2
