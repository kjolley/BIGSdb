ALTER TABLE loci ADD no_submissions boolean;
ALTER TABLE loci ADD id_check_type_alleles boolean;
ALTER TABLE loci ADD id_check_threshold float;

ALTER TABLE schemes ADD no_submissions boolean;
ALTER TABLE schemes ADD disable boolean;
ALTER TABLE schemes RENAME description TO name;
ALTER TABLE schemes ADD description text;

CREATE TABLE scheme_flags (
scheme_id int NOT NULL,
flag text NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(scheme_id,flag),
CONSTRAINT sfl_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE,
CONSTRAINT sfl_scheme_id FOREIGN KEY (scheme_id) REFERENCES schemes
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON scheme_flags TO apache;

CREATE TABLE scheme_links (
scheme_id int NOT NULL,
url text NOT NULL,
description text NOT NULL,
link_order int,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(scheme_id,url),
CONSTRAINT sli_scheme_id FOREIGN KEY (scheme_id) REFERENCES schemes
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT sli_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON scheme_links TO apache;

CREATE TABLE scheme_refs (
scheme_id int NOT NULL,
pubmed_id int NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(scheme_id,pubmed_id),
CONSTRAINT sre_scheme_id FOREIGN KEY (scheme_id) REFERENCES schemes
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT sre_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON scheme_refs TO apache;

ALTER TABLE locus_links DROP CONSTRAINT locus_links_pkey;
ALTER TABLE locus_links ADD CONSTRAINT locus_links_pkey PRIMARY KEY(locus,url);
