WITH expected(table_name, column_name) AS (
  VALUES
('users','phone'),
('users','username'),
('webhook_event_logs','id'),
('webhook_event_logs','payload_preview'),
('webhook_event_logs','provider'),
('webhook_event_logs','received_at'),
('whatsapp_report_schedules','business_id'),
('whatsapp_report_schedules','created_at'),
('whatsapp_report_schedules','enabled'),
('whatsapp_report_schedules','hour'),
('whatsapp_report_schedules','id'),
('whatsapp_report_schedules','last_sent_at'),
('whatsapp_report_schedules','minute'),
('whatsapp_report_schedules','schedule_type'),
('whatsapp_report_schedules','timezone'),
('whatsapp_report_schedules','to_e164'),
('whatsapp_report_schedules','updated_at')
)
SELECT e.table_name, e.column_name
FROM expected e
WHERE NOT EXISTS (
  SELECT 1 FROM information_schema.columns col
  WHERE col.table_schema = 'public'
    AND col.table_name = e.table_name
    AND col.column_name = e.column_name
)
ORDER BY 1, 2;