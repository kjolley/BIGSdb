ALTER TABLE loci ADD flag_table boolean;
UPDATE loci SET flag_table = true;
ALTER TABLE loci ALTER COLUMN flag_table SET NOT NULL;

ALTER TABLE user_permissions DROP COLUMN set_user_permissions;

