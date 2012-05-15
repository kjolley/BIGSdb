ALTER TABLE loci ADD flag_table boolean;
UPDATE loci SET flag_table = true;
ALTER TABLE loci ALTER COLUMN flag_table SET NOT NULL;

ALTER TABLE user_permissions DROP COLUMN set_user_permissions;

ALTER TABLE sequence_bin ADD COLUMN run_id text;
ALTER TABLE sequence_bin ADD COLUMN assembly_id text;
