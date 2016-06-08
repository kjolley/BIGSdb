-- Add code for future planned functionality
CREATE TABLE retired_isolates (
isolate_id int NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (isolate_id),
CONSTRAINT ri_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON retired_isolates TO apache;

CREATE OR REPLACE FUNCTION check_retired_isolates() RETURNS TRIGGER AS $check_retired_isolates$
	BEGIN
		IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
			PERFORM * FROM retired_isolates WHERE isolate_id=NEW.id;
			IF FOUND THEN 
				RAISE EXCEPTION 'Isolate id % has been retired.',NEW.id;
			END IF;
		END IF;
		RETURN NEW;
	END;
$check_retired_isolates$ LANGUAGE plpgsql;

CREATE TRIGGER check_retired_isolates AFTER INSERT OR UPDATE ON isolates
	FOR EACH ROW
	EXECUTE PROCEDURE check_retired_isolates();
	
CREATE OR REPLACE FUNCTION check_isolate_defined() RETURNS TRIGGER AS $check_isolate_defined$
	BEGIN
		IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
			PERFORM * FROM isolates WHERE id=NEW.isolate_id;
			IF FOUND THEN 
				RAISE EXCEPTION 'Isolate id % still exists - delete it before retiring.',NEW.isolate_id;
			END IF;
		END IF;
		RETURN NEW;
	END;
$check_isolate_defined$ LANGUAGE plpgsql;

CREATE TRIGGER check_isolate_defined AFTER INSERT OR UPDATE ON retired_isolates
	FOR EACH ROW
	EXECUTE PROCEDURE check_isolate_defined();
	
CREATE TABLE tag_designations (
allele_sequence_id bigint NOT NULL,
allele_designation_id bigint NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(allele_sequence_id,allele_designation_id),
CONSTRAINT td_allele_sequence_id FOREIGN KEY(allele_sequence_id) REFERENCES allele_sequences
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT td_allele_designation_id FOREIGN KEY(allele_designation_id) REFERENCES allele_designations
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT td_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON tag_designations TO apache;
