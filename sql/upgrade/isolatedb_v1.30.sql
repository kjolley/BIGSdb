ALTER TABLE schemes ADD recommended boolean NOT NULL DEFAULT FALSE;
ALTER TABLE schemes ADD quality_metric boolean NOT NULL DEFAULT FALSE;
ALTER TABLE schemes ADD quality_metric_good_threshold int;
ALTER TABLE schemes ADD quality_metric_bad_threshold int;
UPDATE schemes SET allow_missing_loci=FALSE WHERE allow_missing_loci IS NULL;
ALTER TABLE schemes ALTER COLUMN allow_missing_loci SET default FALSE;
ALTER TABLE schemes ALTER COLUMN allow_missing_loci set NOT NULL;
