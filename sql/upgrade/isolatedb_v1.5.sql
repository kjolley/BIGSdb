CREATE TABLE sets (
id int NOT NULL,
description text NOT NULL,
long_description text,
display_order int,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(id),
CONSTRAINT s_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON sets TO apache;

CREATE TABLE set_loci (
set_id int NOT NULL,
locus text NOT NULL,
set_name text,
formatted_set_name text,
set_common_name text,
formatted_set_common_name text,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(set_id, locus),
CONSTRAINT sl_set_id FOREIGN KEY (set_id) REFERENCES sets
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT sl_locus FOREIGN KEY (locus) REFERENCES loci
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT sl_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON set_loci TO apache;

CREATE TABLE set_schemes (
set_id int NOT NULL,
scheme_id int NOT NULL,
set_name text,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(set_id, scheme_id),
CONSTRAINT ss_set_id FOREIGN KEY (set_id) REFERENCES sets
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT ss_scheme_id FOREIGN KEY (scheme_id) REFERENCES schemes
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT ss_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON set_schemes TO apache;

CREATE TABLE set_metadata (
set_id int NOT NULL,
metadata_id text NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(set_id, metadata_id),
CONSTRAINT sm_set_id FOREIGN KEY (set_id) REFERENCES sets
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT sm_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON set_metadata TO apache;

CREATE TABLE set_view (
set_id int NOT NULL,
view text NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(set_id),
CONSTRAINT sv_set_id FOREIGN KEY (set_id) REFERENCES sets
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT sv_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON set_view TO apache;

ALTER TABLE loci ADD COLUMN match_longest boolean;
ALTER TABLE loci ADD COLUMN formatted_name text;
ALTER TABLE loci ADD COLUMN formatted_common_name text;



