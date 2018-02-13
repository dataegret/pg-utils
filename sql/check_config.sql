/* This query is used for getting non default configuration parameters in PostgreSQL.
   For user/client sessions you can see modified parameters, but reset_val will contain value from configuration file (I hope).
   If you see (*) before config name it means that parameter has default value.
   If you see (c) after config name it means that parameter was changed for client session or by another reason (database, user, etc).
   If you see !!! after config name it means that parameter were changed in file but still not apllied.
   All fields in report are aligned by width for simplifying a compare procedures.
*/
with icp (name) as (
  values ('listen_addresses'), ('max_connections'), ('superuser_reserved_connections'), ('shared_buffers')
       , ('work_mem'), ('maintenance_work_mem'), ('shared_preload_libraries'), ('vacuum_cost_delay')
       , ('vacuum_cost_page_hit'), ('vacuum_cost_page_miss'), ('vacuum_cost_page_dirty'), ('vacuum_cost_limit')
       , ('bgwriter_delay'), ('bgwriter_lru_maxpages'), ('bgwriter_lru_multiplier'), ('effective_io_concurrency')
       , ('max_worker_processes'), ('wal_level'), ('synchronous_commit'), ('checkpoint_timeout')
       , ('min_wal_size'), ('max_wal_size'), ('checkpoint_completion_target'), ('max_wal_senders')
       , ('hot_standby'), ('max_standby_streaming_delay'), ('hot_standby_feedback'), ('effective_cache_size')
       , ('log_directory'), ('log_filename'), ('log_min_duration_statement'), ('log_checkpoints')
       , ('log_line_prefix'), ('log_lock_waits'), ('log_replication_commands'), ('log_temp_files')
       , ('track_io_timing'), ('track_functions'), ('track_activity_query_size'), ('log_autovacuum_min_duration')
       , ('autovacuum_max_workers'), ('autovacuum_naptime'), ('autovacuum_vacuum_threshold')
       , ('autovacuum_analyze_threshold'), ('autovacuum_vacuum_scale_factor'), ('autovacuum_analyze_scale_factor')
       , ('autovacuum_vacuum_cost_delay'), ('vacuum_freeze_min_age'), ('vacuum_freeze_table_age')
       , ('pg_stat_statements.max'), ('pg_stat_statements.track')
       , ('pg_stat_statements.track_utility'), ('pg_stat_statements.save')
)
select rpad (case when source in ('default', 'override') then '(*) ' else '    ' end || 
             rpad (name, 35) ||
             case when setting != reset_val then ' (c)' else '' end ||
             case when pending_restart then ' !!!' else '' end
            , 47) as name
     , rpad (case when (unit = '8kB' and setting != '-1') then pg_size_pretty (setting::bigint * 8192) 
                  when (unit = 'kB' and  setting != '-1') then pg_size_pretty (setting::bigint * 1024) 
                  else setting end, 25) as setting
     , rpad (case when unit in ('8kB', 'kB') then 'byte' else unit end, 4) as unit
     , rpad (case when (unit = '8kB' and reset_val != '-1') then pg_size_pretty (reset_val::bigint * 8192) 
                  when (unit = 'kB' and  reset_val != '-1') then pg_size_pretty (reset_val::bigint * 1024) 
                  else reset_val end, 25) as reset_val
     , rpad (case when (unit = '8kB' and boot_val != '-1') then pg_size_pretty (boot_val::bigint * 8192) 
                  when (unit = 'kB' and  boot_val != '-1') then pg_size_pretty (boot_val::bigint * 1024) 
                  else boot_val end, 25) as boot_val
     , rpad (case source
               when 'environment variable' then 'env'
               when 'configuration file' then '.conf'
               when 'configuration file' then '.conf'
               else source
             end
            , 13) as source
     --, sourcefile
  from pg_settings
 where (sourcefile is not null
    or pending_restart
    or setting != boot_val
    or reset_val != boot_val
    or exists (select 1 from icp where icp.name = pg_settings.name)
    or source not in ('default', 'override'))
   and (name, setting) not in ( ('log_filename', 'postgresql-%Y-%m-%d.log')
                              , ('log_checkpoints', 'on')
                              , ('logging_collector', 'on')
                              , ('log_line_prefix', '%m %p %u@%d from %h [vxid:%v txid:%x] [%i] ')
                              , ('log_replication_commands', 'on')
                              , ('log_destination', 'stderr')
                              , ('log_file_mode', '0600')
                              , ('unix_socket_permissions', '0777')
                              , ('transaction_read_only', 'on')
                              , ('transaction_read_only', 'off')
                              , ('application_name', 'psql')
                              , ('archive_command', '(disabled)')
                              )
 order by category, name;