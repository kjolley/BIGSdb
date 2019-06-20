ALTER TABLE eav_fields ADD category text;
ALTER TABLE eav_fields ADD no_submissions boolean;
UPDATE eav_fields SET no_submissions=no_curate;
ALTER TABLE eav_fields ALTER COLUMN no_submissions SET NOT NULL;
