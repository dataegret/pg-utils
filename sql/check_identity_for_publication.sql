SELECT pt.tablename,
        CASE pc.relreplident
          WHEN 'd' THEN 'default'
          WHEN 'n' THEN 'nothing'
          WHEN 'f' THEN 'full'
          WHEN 'i' THEN 'index'
       END AS replica_identity
FROM pg_publication_tables pt
left 
join pg_class pc  on (pt.tablename::regclass = pc.oid)
WHERE pt.pubname = 'flink_pub';


