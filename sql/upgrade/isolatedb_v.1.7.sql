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

ALTER TABLE allele_sequences ADD isolate_id int;
UPDATE allele_sequences SET isolate_id = (SELECT isolate_id FROM sequence_bin WHERE sequence_bin.id = allele_sequences.seqbin_id);
ALTER TABLE allele_sequences ALTER COLUMN isolate_id SET NOT NULL;
ALTER TABLE allele_sequences ADD CONSTRAINT as_isolate_id FOREIGN KEY(isolate_id) REFERENCES isolates(id)
ON DELETE CASCADE
ON UPDATE CASCADE;
CREATE INDEX i_as3 ON allele_sequences(isolate_id);

CREATE LANGUAGE 'plpgsql';

-- Set isolate_id in allele_sequences table when adding or updating allele_sequences.
CREATE OR REPLACE FUNCTION set_allele_sequences_isolate_id_field() RETURNS TRIGGER AS $set_allele_sequences_isolate_id_field$
	DECLARE set_isolate_id integer;		
	BEGIN
		SELECT isolate_id INTO set_isolate_id FROM sequence_bin WHERE id=NEW.seqbin_id;
		NEW.isolate_id := set_isolate_id;
		RETURN NEW;
	END; 
$set_allele_sequences_isolate_id_field$ LANGUAGE plpgsql;

CREATE TRIGGER set_allele_sequences_isolate_id_field BEFORE INSERT OR UPDATE ON allele_sequences
	FOR EACH ROW
	EXECUTE PROCEDURE set_allele_sequences_isolate_id_field();
	
-- Update isolate_id in allele_sequences table after updating sequence bin record.
CREATE OR REPLACE FUNCTION set_allele_sequences_isolate_id_field2() RETURNS TRIGGER AS $set_allele_sequences_isolate_id_field2$
	BEGIN
		IF (NEW.isolate_id != OLD.isolate_id) THEN
			UPDATE allele_sequences SET isolate_id=NEW.isolate_id WHERE seqbin_id=NEW.id;
		END IF;
		RETURN NULL;
	END; 
$set_allele_sequences_isolate_id_field2$ LANGUAGE plpgsql;
	
CREATE TRIGGER set_allele_sequences_isolate_id_field2 AFTER UPDATE ON sequence_bin
	FOR EACH ROW
	EXECUTE PROCEDURE set_allele_sequences_isolate_id_field2();
