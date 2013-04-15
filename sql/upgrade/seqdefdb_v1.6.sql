ALTER TABLE client_dbase_schemes ADD client_scheme_id int;

ALTER TABLE loci ADD match_longest boolean;

ALTER TABLE schemes ADD allow_missing_loci boolean;

ALTER TABLE sequences ADD comments text;
ALTER TABLE sequences DROP CONSTRAINT seq_loci;
ALTER TABLE sequences ADD CONSTRAINT seq_loci FOREIGN KEY (locus) REFERENCES loci ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE sets ADD hidden boolean;
