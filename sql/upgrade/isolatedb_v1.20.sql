ALTER TABLE eav_fields ADD conditional_formatting text;
ALTER TABLE eav_fields ADD html_link_text text;
ALTER TABLE eav_fields ADD html_message text;
ALTER TABLE eav_fields ADD no_curate boolean;
UPDATE eav_fields SET no_curate = FALSE;
ALTER TABLE eav_fields ALTER COLUMN no_curate SET NOT NULL;
