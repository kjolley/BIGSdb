CREATE TABLE locus_stats (
locus text NOT NULL,
datestamp date,
allele_count int NOT NULL,
PRIMARY KEY (locus),
CONSTRAINT ls_locus FOREIGN KEY (locus) REFERENCES loci
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON locus_stats TO apache;

INSERT INTO locus_stats(locus,datestamp,allele_count) 
SELECT loci.id,MAX(sequences.datestamp),COUNT(sequences.allele_id) 
FROM loci LEFT JOIN sequences ON loci.id=sequences.locus 
WHERE allele_id NOT IN ('N','0') OR allele_id IS NULL 
GROUP BY loci.id;

-- Add new locus_stats value when creating new locus.
CREATE OR REPLACE FUNCTION add_locus_stats_record() RETURNS TRIGGER AS $add_locus_stats_record$
	BEGIN
		INSERT INTO locus_stats(locus,allele_count) VALUES (NEW.id,0);
		RETURN NULL;
	END; 
$add_locus_stats_record$ LANGUAGE plpgsql;

CREATE TRIGGER add_locus_stats_record AFTER INSERT ON loci
	FOR EACH ROW
	EXECUTE PROCEDURE add_locus_stats_record();

-- Update stats when adding or removing alleles.
CREATE OR REPLACE FUNCTION update_locus_stats() RETURNS TRIGGER AS $update_locus_stats$
	DECLARE
		delta_allele_count	integer;
	BEGIN
		IF (TG_OP = 'DELETE' AND OLD.allele_id NOT IN ('0','N')) THEN
			UPDATE locus_stats SET datestamp='now',allele_count=allele_count-1 WHERE locus=OLD.locus;
			PERFORM locus FROM sequences WHERE locus=OLD.locus;
			IF NOT FOUND THEN  --There are no more alleles for this locus.
				UPDATE locus_stats SET datestamp=null WHERE locus=OLD.locus;
			END IF;
		ELSIF (TG_OP = 'INSERT' AND NEW.allele_id NOT IN ('0','N')) THEN
			UPDATE locus_stats SET datestamp='now',allele_count=allele_count+1 WHERE locus=NEW.locus;
		END IF;
		RETURN NULL;
	END;
$update_locus_stats$ LANGUAGE plpgsql;

CREATE TRIGGER update_locus_stats AFTER INSERT OR DELETE ON sequences
	FOR EACH ROW
	EXECUTE PROCEDURE update_locus_stats();