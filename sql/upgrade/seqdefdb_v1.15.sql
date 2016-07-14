ALTER TABLE loci ADD no_submissions boolean;

ALTER TABLE schemes ADD no_submissions boolean;
ALTER TABLE schemes ADD display boolean;
UPDATE schemes SET display=TRUE;
