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

CREATE TABLE peptide_mutations (
id int NOT NULL UNIQUE,
locus text NOT NULL,
wild_type_allele_id text,
reported_position int NOT NULL,
locus_position int NOT NULL,
wild_type_aa text NOT NULL,
variant_aa text NOT NULL,
flanking_length int NOT NULL,
curator integer NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (id),
CONSTRAINT pm_wild_type_allele_id FOREIGN KEY (locus,wild_type_allele_id) REFERENCES sequences(locus,allele_id)
ON DELETE NO ACTION
ON UPDATE CASCADE,
CONSTRAINT pm_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON peptide_mutations TO apache;

CREATE TABLE sequences_peptide_mutations (
locus text NOT NULL,
allele_id text NOT NULL,
mutation_id int NOT NULL,
amino_acid char(1) NOT NULL,
is_wild_type boolean NOT NULL,
is_mutation boolean NOT NULL,
curator integer NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(locus, allele_id, mutation_id),
CONSTRAINT spm_sequences FOREIGN KEY (locus,allele_id) REFERENCES sequences
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT spm_mutation_id FOREIGN KEY (mutation_id) REFERENCES peptide_mutations
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT spm_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON sequences_peptide_mutations TO apache;

CREATE TABLE dna_mutations (
id int NOT NULL UNIQUE,
locus text NOT NULL,
wild_type_allele_id text,
reported_position int NOT NULL,
locus_position int NOT NULL,
wild_type_nuc text NOT NULL,
variant_nuc text NOT NULL,
flanking_length int NOT NULL,
curator integer NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (id),
CONSTRAINT dm_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON dna_mutations TO apache;

CREATE TABLE sequences_dna_mutations (
locus text NOT NULL,
allele_id text NOT NULL,
mutation_id int NOT NULL,
nucleotide char(1) NOT NULL,
is_wild_type boolean NOT NULL,
is_mutation boolean NOT NULL,
curator integer NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(locus, allele_id, mutation_id),
CONSTRAINT sdm_sequences FOREIGN KEY (locus,allele_id) REFERENCES sequences
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT sdm_mutation_id FOREIGN KEY (mutation_id) REFERENCES dna_mutations
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT sdm_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON sequences_dna_mutations TO apache;
