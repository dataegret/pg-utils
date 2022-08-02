-- List active indexing sessions and their progress
SELECT p.pid
     , date_trunc('second',now() - a.xact_start)                                      AS duration
     , p.datname                                                                      AS database
     , p.index_relid::regclass                                                        AS index
     , pg_size_pretty(pg_total_relation_size(index_relid)) || ' / ' || coalesce(pg_size_pretty(pg_total_relation_size((SELECT DISTINCT indexrelid FROM pg_locks l JOIN pg_index i ON l.relation = i.indexrelid WHERE l.pid = p.pid AND l.locktype = 'relation' AND i.indexrelid != p.index_relid))), '-') AS "new / old size"
     , p.command, p.phase
     , CASE WHEN blocks_total > 0 THEN format('%s%% of %s', round(blocks_done::numeric / blocks_total * 100, 1), blocks_total) END AS blocks
     , CASE WHEN tuples_total > 0 THEN format('%s%% of %s', round(tuples_done::numeric / tuples_total * 100, 1), tuples_total) END AS tuples
     , (SELECT COUNT(*) FROM pg_stat_activity a2 where a2.query = a.query) AS workers
     , CASE WHEN lockers_total > lockers_done AND p.phase ~ 'waiting'
            THEN format('%s ( %s / %s )', current_locker_pid, lockers_done, lockers_total) END AS waiting
     , coalesce(wait_event_type ||'.'|| wait_event, 'f')                              AS wait_event
  FROM pg_stat_progress_create_index p JOIN pg_stat_activity a using (pid) ORDER BY duration DESC;