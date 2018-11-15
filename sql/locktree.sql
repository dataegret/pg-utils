WITH RECURSIVE l AS (
  SELECT pid, locktype, granted,
    array_position(ARRAY['AccessShare','RowShare','RowExclusive','ShareUpdateExclusive','Share','ShareRowExclusive','Exclusive','AccessExclusive'], left(mode,-4)) m,
    ROW(locktype,database,relation,page,tuple,virtualxid,transactionid,classid,objid,objsubid) obj FROM pg_locks
), pairs AS (
  SELECT w.pid waiter, l.pid locker, l.obj, l.m
    FROM l w JOIN l ON l.obj IS NOT DISTINCT FROM w.obj AND l.locktype=w.locktype AND NOT l.pid=w.pid AND l.granted
   WHERE NOT w.granted
     AND NOT EXISTS ( SELECT FROM l i WHERE i.pid=l.pid AND i.locktype=l.locktype AND i.obj IS NOT DISTINCT FROM l.obj AND i.m > l.m )
), leads AS (
  SELECT o.locker, 1::int lvl, count(*) q, ARRAY[locker] track, false AS cycle FROM pairs o GROUP BY o.locker
  UNION ALL
  SELECT i.locker, leads.lvl+1, (SELECT count(*) FROM pairs q WHERE q.locker=i.locker), leads.track||i.locker, i.locker=ANY(leads.track)
    FROM pairs i, leads WHERE i.waiter=leads.locker AND NOT cycle
), tree AS (
  SELECT locker pid,locker dad,locker root,CASE WHEN cycle THEN track END dl, NULL::record obj,0 lvl,locker::text path,array_agg(locker) OVER () all_pids FROM leads o
   WHERE (cycle AND NOT EXISTS (SELECT FROM leads i WHERE i.locker=ANY(o.track) AND (i.lvl>o.lvl OR i.q<o.q)))
      OR (NOT cycle AND NOT EXISTS (SELECT FROM pairs WHERE waiter=o.locker) AND NOT EXISTS (SELECT FROM leads i WHERE i.locker=o.locker AND i.lvl>o.lvl))
  UNION ALL
  SELECT w.waiter pid,tree.pid,tree.root,CASE WHEN w.waiter=ANY(tree.dl) THEN tree.dl END,w.obj,tree.lvl+1,tree.path||'.'||w.waiter,all_pids || array_agg(w.waiter) OVER ()
    FROM tree JOIN pairs w ON tree.pid=w.locker AND NOT w.waiter = ANY ( all_pids )
)
SELECT (clock_timestamp() - a.xact_start)::interval(0) AS ts_age,
       (clock_timestamp() - a.state_change)::interval(0) AS change_age,
       a.datname,a.usename,a.client_addr,
       --w.obj wait_on_object,
       tree.pid,replace(a.state, 'idle in transaction', 'idletx') state,
       lvl,(SELECT count(*) FROM tree p WHERE p.path ~ ('^'||tree.path) AND NOT p.path=tree.path) blocked,
       CASE WHEN tree.pid=ANY(tree.dl) THEN '!>' ELSE repeat(' .', lvl) END||' '||trim(left(regexp_replace(a.query, E'\\s+', ' ', 'g'),100)) query
  FROM tree
  LEFT JOIN pairs w ON w.waiter=tree.pid AND w.locker=tree.dad
  JOIN pg_stat_activity a USING (pid)
  JOIN pg_stat_activity r ON r.pid=tree.root
 ORDER BY (now() - r.xact_start), path;
