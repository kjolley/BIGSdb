ALTER TABLE schemes DROP COLUMN IF EXISTS dbase_st_field;
ALTER TABLE schemes DROP COLUMN IF EXISTS dbase_st_descriptor;
ALTER TABLE schemes RENAME description TO name;
ALTER TABLE schemes ADD description text;
ALTER TABLE schemes ADD dbase_id int;
UPDATE schemes SET dbase_id=CAST(REGEXP_REPLACE(dbase_table,'^mv_scheme_','') AS int) WHERE dbase_table IS NOT NULL;
ALTER TABLE schemes DROP COLUMN dbase_table;

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

ALTER TABLE loci DROP COLUMN flag_table;
ALTER TABLE loci DROP COLUMN dbase_table;
ALTER TABLE loci DROP COLUMN dbase_id_field;
ALTER TABLE loci DROP COLUMN dbase_id2_field;
ALTER TABLE loci DROP COLUMN dbase_seq_field;
ALTER TABLE loci RENAME COLUMN dbase_id2_value TO dbase_id;
