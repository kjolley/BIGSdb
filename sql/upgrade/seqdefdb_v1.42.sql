ALTER TABLE schemes ADD allow_presence boolean;
UPDATE schemes SET allow_presence = FALSE;
ALTER TABLE schemes ALTER COLUMN allow_presence SET NOT NULL;
ALTER TABLE schemes ALTER COLUMN allow_presence SET DEFAULT FALSE;

UPDATE schemes SET allow_missing_loci = FALSE WHERE allow_missing_loci IS NULL;
ALTER TABLE schemes ALTER COLUMN allow_missing_loci SET NOT NULL;
ALTER TABLE schemes ALTER COLUMN allow_missing_loci SET DEFAULT FALSE;

UPDATE schemes SET disable = FALSE WHERE disable IS NULL;
ALTER TABLE schemes ALTER COLUMN disable SET NOT NULL;
ALTER TABLE schemes ALTER COLUMN disable SET DEFAULT FALSE;

UPDATE schemes SET no_submissions = FALSE WHERE no_submissions IS NULL;
ALTER TABLE schemes ALTER COLUMN no_submissions SET NOT NULL;
ALTER TABLE schemes ALTER COLUMN no_submissions SET DEFAULT FALSE;
