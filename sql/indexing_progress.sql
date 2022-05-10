-- List active indexing sessions and their progress
SELECT p.pid
     , date_trunc('second',now() - a.xact_start)                                      AS dur
     , coalesce(wait_event_type ||'.'|| wait_event, 'f')                              AS wait
     , p.datname
     , p.index_relid::regclass                                                        AS ind
     , round(pg_total_relation_size(index_relid)/1024.0/1024)                         AS ind_ttl_mb
     , p.command, p.phase
     , CASE WHEN lockers_total > lockers_done AND p.phase ~ 'waiting'
            THEN format('%s ( %s / %s )', current_locker_pid, lockers_done, lockers_total) END AS waiting
     , CASE WHEN blocks_total > 0 THEN format('%s%% of %s', round(blocks_done::numeric / blocks_total * 100), blocks_total) END AS blocks
     , CASE WHEN tuples_total > 0 THEN format('%s%% of %s', round(tuples_done::numeric / tuples_total * 100), tuples_total) END AS tuples
     , CASE WHEN partitions_total > 0 THEN format('%s%% of %s', round(partitions_done::numeric / partitions_total * 100), partitions_total) END AS partitions
  FROM pg_stat_progress_create_index p JOIN pg_stat_activity a using (pid) ORDER BY dur DESC;

