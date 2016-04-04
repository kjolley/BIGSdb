-- Cleanup newlines from locus_descriptions
UPDATE locus_descriptions SET product=regexp_replace(product,'\r|\n',' ','g');
UPDATE locus_descriptions SET product=regexp_replace(product,'\s+$','');
UPDATE locus_descriptions SET full_name=regexp_replace(full_name,'\r|\n',' ','g');
UPDATE locus_descriptions SET full_name=regexp_replace(full_name,'\s+$','');
UPDATE locus_descriptions SET description=regexp_replace(description,'\r|\n',' ','g');
UPDATE locus_descriptions SET description=regexp_replace(description,'\s+$','');

CREATE TABLE locus_stats (
locus text NOT NULL,
datestamp date,
allele_count int NOT NULL,
min_length int,
max_length int,
PRIMARY KEY (locus),
CONSTRAINT ls_locus FOREIGN KEY (locus) REFERENCES loci
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON locus_stats TO apache;

INSERT INTO locus_stats(locus,datestamp,allele_count,min_length,max_length) 
SELECT loci.id,MAX(sequences.datestamp),COUNT(sequences.allele_id),MIN(LENGTH(sequence)),MAX(LENGTH(sequence)) 
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
		current_min_length integer;
		current_max_length integer;
		current_datestamp date;
		allele_length integer;
	BEGIN
		IF (TG_OP = 'DELETE' AND OLD.allele_id NOT IN ('0','N')) THEN
			PERFORM locus FROM sequences WHERE locus=OLD.locus;
			IF NOT FOUND THEN  --There are no more alleles for this locus.
				UPDATE locus_stats SET datestamp=null,allele_count=0,min_length=null,max_length=null WHERE locus=OLD.locus;
			ELSE
				SELECT MIN(LENGTH(sequence)),MAX(LENGTH(sequence)),MAX(datestamp) INTO 
				current_min_length,current_max_length,current_datestamp FROM sequences WHERE 
				locus=OLD.locus AND allele_id NOT IN ('0','N');
				UPDATE locus_stats SET datestamp=current_datestamp,allele_count=allele_count-1,
				min_length=current_min_length,max_length=current_max_length WHERE locus=OLD.locus;
			END IF;
		ELSIF (TG_OP = 'INSERT' AND NEW.allele_id NOT IN ('0','N')) THEN
			UPDATE locus_stats SET datestamp='now',allele_count=allele_count+1 WHERE locus=NEW.locus;
			SELECT min_length,max_length INTO current_min_length,current_max_length FROM locus_stats WHERE locus=NEW.locus;
			allele_length := LENGTH(NEW.sequence);
			IF (current_min_length IS NULL OR allele_length < current_min_length) THEN
				UPDATE locus_stats SET min_length = allele_length WHERE locus=NEW.locus;
			END IF;
			IF (current_max_length IS NULL OR allele_length > current_max_length) THEN
				UPDATE locus_stats SET max_length = allele_length WHERE locus=NEW.locus;
			END IF;
		END IF;
		RETURN NULL;
	END;
$update_locus_stats$ LANGUAGE plpgsql;

CREATE TRIGGER update_locus_stats AFTER INSERT OR DELETE ON sequences
	FOR EACH ROW
	EXECUTE PROCEDURE update_locus_stats();