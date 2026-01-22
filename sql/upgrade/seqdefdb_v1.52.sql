UPDATE db_attributes SET value='52' WHERE field='version';

ALTER TABLE dna_mutations ADD CONSTRAINT dm_wild_type_allele_id 
 FOREIGN KEY (locus,wild_type_allele_id) REFERENCES sequences(locus,allele_id)
 ON DELETE NO ACTION ON UPDATE CASCADE;
ALTER TABLE dna_mutations ADD CONSTRAINT dm_locus 
 FOREIGN KEY (locus) REFERENCES loci 
 ON DELETE CASCADE ON UPDATE CASCADE;
 
ALTER TABLE peptide_mutations ADD CONSTRAINT pm_locus 
 FOREIGN KEY (locus) REFERENCES loci
 ON DELETE CASCADE
 ON UPDATE CASCADE;
 
ALTER TABLE scheme_curators ADD hide_public bool;

ALTER TABLE scheme_fields ADD submissions bool;
UPDATE scheme_fields SET submissions = FALSE;
ALTER TABLE scheme_fields ALTER COLUMN submissions SET NOT NULL;

CREATE TABLE profile_submission_fields (
submission_id text NOT NULL,
profile_id text NOT NULL,
field text NOT NULL,
value text NOT NULL,
PRIMARY KEY(submission_id,profile_id,field),
CONSTRAINT psf_submission_id FOREIGN KEY (submission_id,profile_id) REFERENCES profile_submission_profiles(submission_id,profile_id)
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON profile_submission_fields TO apache;
