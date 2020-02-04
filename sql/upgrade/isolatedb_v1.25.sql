ALTER TABLE user_groups ADD co_curate_private boolean;
UPDATE user_groups SET co_curate_private = FALSE;
ALTER TABLE user_groups ALTER COLUMN co_curate_private SET NOT NULL;
