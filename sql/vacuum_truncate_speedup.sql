\prompt 'This utility will constantly read (until stopped) tail of given table to speed up vacuum truncate operation.\nMight be useful when pgcompacttable couldn''t shrink large table in reasonable time because of conflicting lock requests.\nQuery will return 0 if there is anything left to truncate.\nPlease enter table name: ' tablename
\prompt 'Please enter number of pages to read [10000]: ' pages
\prompt 'Please enter interval between iterations in seconds [1]: ' interval
\timing on
\pset tuples_only on
select count(*) from (select * from :tablename where ctid = ANY(array(select (i,1)::text::tid from generate_series(pg_relation_size(:'tablename')/current_setting('block_size')::int - (case when :'pages' = '' then '10000' else :'pages' end)::int, pg_relation_size(:'tablename')/current_setting('block_size')::int) as g(i)))) as a;
\watch :interval