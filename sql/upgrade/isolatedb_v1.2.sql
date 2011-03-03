CREATE TABLE pcr (
id int NOT NULL,
description text NOT NULL,
primer1 text NOT NULL,
primer2 text NOT NULL,
min_length int,
max_length int,
max_primer_mismatch int,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (id),
CONSTRAINT p_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON pcr TO apache;

CREATE TABLE pcr_locus (
pcr_id int NOT NULL,
locus text NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (pcr_id,locus),
CONSTRAINT pl_pcr FOREIGN KEY (pcr_id) REFERENCES pcr
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT pl_loci FOREIGN KEY (locus) REFERENCES loci
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT pl_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON pcr_locus TO apache;

ALTER TABLE loci ADD pcr_filter bool;
ALTER TABLE loci ADD probe_filter bool;

CREATE TABLE probes (
id int NOT NULL,
description text NOT NULL,
sequence text NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (id),
CONSTRAINT pr_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON probes TO apache;

CREATE TABLE probe_locus (
probe_id int NOT NULL,
locus text NOT NULL,
max_distance int NOT NULL,
min_alignment int,
max_mismatch int,
max_gaps int,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (probe_id,locus),
CONSTRAINT prl_probe FOREIGN KEY (probe_id) REFERENCES probes
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT prl_loci FOREIGN KEY (locus) REFERENCES loci
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT prl_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON probe_locus TO apache;

ALTER TABLE user_permissions ADD modify_probes boolean;

CREATE INDEX i_i1 ON isolates (datestamp);
CREATE INDEX i_ad4 ON allele_designations (datestamp);
CREATE INDEX i_as2 ON allele_sequences (datestamp);


