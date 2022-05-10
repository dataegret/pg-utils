-- List active vacuums and their progress
SELECT p.pid
     , date_trunc('second',now() - a.xact_start)                                      AS dur
     , coalesce(wait_event_type ||'.'|| wait_event, 'f')                              AS wait
     , CASE WHEN a.query ~ 'to prevent wraparound' THEN 'freeze' ELSE 'regular' END   AS mode
     , (SELECT datname FROM pg_database WHERE oid = p.datid)                          AS dat
     , p.relid::regclass                                                              AS tab
     , p.phase
     , round((p.heap_blks_total * current_setting('block_size')::int)/1024.0/1024)    AS tab_mb
     , round(pg_total_relation_size(relid)/1024.0/1024)                               AS ttl_mb
     , round((p.heap_blks_scanned * current_setting('block_size')::int)/1024.0/1024)  AS scan_mb
     , round((p.heap_blks_vacuumed * current_setting('block_size')::int)/1024.0/1024) AS vac_mb
     , (100 * p.heap_blks_scanned / nullif(p.heap_blks_total,0))                      AS scan_pct
     , (100 * p.heap_blks_vacuumed / nullif(p.heap_blks_total,0))                     AS vac_pct
     , p.index_vacuum_count                                                           AS ind_vac_cnt
     , round(p.num_dead_tuples * 100.0 / nullif(p.max_dead_tuples, 0),1)              AS dead_pct
  FROM pg_stat_progress_vacuum p JOIN pg_stat_activity a using (pid) ORDER BY dur DESC;

