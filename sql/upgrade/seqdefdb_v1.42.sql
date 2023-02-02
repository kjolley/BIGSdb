CREATE TABLE peptide_mutations (
id serial NOT NULL UNIQUE,
locus text NOT NULL,
wild_type_aa char(1) NOT NULL,
variant_aa char(1)[] NOT NULL,
curator integer NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (id),
CONSTRAINT pm_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON peptide_mutations TO apache;

CREATE TABLE dna_mutations (
id serial NOT NULL UNIQUE,
locus text NOT NULL,
wt_nuc char(1) NOT NULL,
variant_nuc char(1)[] NOT NULL,
curator integer NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (id),
CONSTRAINT dm_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON dna_variations TO apache;
