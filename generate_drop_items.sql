
SELECT 'SET DROP TABLE (origin=@master, id='||tab_id||'); #',tab_id,tab_nspname||'.'||tab_relname from _slony.sl_table
UNION ALL
SELECT 'SET DROP SEQUENCE (origin=@master, id='||seq_id||'); #',seq_id,seq_nspname||'.'||seq_relname from _slony.sl_sequence
order by 1

