ALTER TABLE eav_fields ADD conditional_formatting text;
ALTER TABLE eav_fields ADD html_link_text text;
ALTER TABLE eav_fields ADD html_message text;
ALTER TABLE eav_fields ADD user_update boolean;
UPDATE eav_fields SET user_update = TRUE;
ALTER TABLE eav_fields ALTER COLUMN user_update SET NOT NULL;
