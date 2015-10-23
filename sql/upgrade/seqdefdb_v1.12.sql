ALTER TABLE sequences ADD validated boolean;
ALTER TABLE sequences ADD exemplar boolean;
ALTER TABLE sequences ADD inferred_allele_id text;
ALTER TABLE sequences ADD CONSTRAINT seq_inferred_allele_id FOREIGN KEY (locus,inferred_allele_id) REFERENCES sequences(locus,allele_id) 
ON DELETE NO ACTION
ON UPDATE CASCADE;
ALTER TABLE locus_extended_attributes ADD main_display boolean;
UPDATE locus_extended_attributes SET main_display=TRUE;
ALTER TABLE locus_extended_attributes ALTER COLUMN main_display SET NOT NULL;

CREATE TABLE retired_allele_ids (
locus text NOT NULL,
allele_id text NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (locus, allele_id),
CONSTRAINT rai_locus FOREIGN KEY (locus) REFERENCES loci
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT rai_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON retired_allele_ids TO apache;

CREATE OR REPLACE FUNCTION check_retired_alleles() RETURNS TRIGGER AS $check_retired_alleles$
	BEGIN
		IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
			PERFORM * FROM retired_allele_ids WHERE (locus,allele_id)=(NEW.locus,NEW.allele_id);
			IF FOUND THEN 
				RAISE EXCEPTION 'Allele id (locus=%,allele_id=%) has been retired.',NEW.locus,NEW.allele_id;
			END IF;
		END IF;
		RETURN NEW;
	END;
$check_retired_alleles$ LANGUAGE plpgsql;

CREATE TRIGGER check_retired_alleles AFTER INSERT OR UPDATE ON sequences
	FOR EACH ROW
	EXECUTE PROCEDURE check_retired_alleles();
	
CREATE OR REPLACE FUNCTION check_allele_defined() RETURNS TRIGGER AS $check_allele_defined$
	BEGIN
		IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
			PERFORM * FROM sequences WHERE (locus,allele_id)=(NEW.locus,NEW.allele_id);
			IF FOUND THEN 
				RAISE EXCEPTION 'Allele id (locus=%,allele_id=%) still exists - delete it before retiring.',NEW.locus,NEW.allele_id;
			END IF;
		END IF;
		RETURN NEW;
	END;
$check_allele_defined$ LANGUAGE plpgsql;

CREATE TRIGGER check_allele_defined AFTER INSERT OR UPDATE ON retired_allele_ids
	FOR EACH ROW
	EXECUTE PROCEDURE check_allele_defined();