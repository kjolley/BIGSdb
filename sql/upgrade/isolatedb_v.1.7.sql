DROP INDEX i_ad1;
DROP INDEX i_ad2;
DROP INDEX i_h1;
DROP INDEX i_pad1;
DROP INDEX i_pad2;
DROP INDEX i_id;

ALTER TABLE loci DROP COLUMN description;

CREATE TABLE sequence_attributes (
key text NOT NULL,
type text NOT NULL,
description text,
curator integer NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (key),
CONSTRAINT sa_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON sequence_attributes TO apache;

CREATE TABLE sequence_attribute_values (
seqbin_id integer NOT NULL,
key text NOT NULL,
value text NOT NULL,
curator integer NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (seqbin_id,key),
CONSTRAINT sav_seqbin FOREIGN KEY (seqbin_id) REFERENCES sequence_bin
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT sav_key FOREIGN KEY (key) REFERENCES sequence_attributes
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT sav_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON sequence_attribute_values TO apache;
