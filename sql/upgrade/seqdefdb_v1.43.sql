CREATE OR REPLACE FUNCTION update_locus_stats() RETURNS TRIGGER AS $update_locus_stats$
	DECLARE
		current_min_length integer;
		current_max_length integer;
		current_datestamp date;
		allele_length integer;
	BEGIN
		IF (TG_OP = 'DELETE' AND OLD.allele_id NOT IN ('0','N','P')) THEN
			PERFORM locus FROM sequences WHERE locus=OLD.locus;
			IF NOT FOUND THEN  --There are no more alleles for this locus.
				UPDATE locus_stats SET datestamp=null,allele_count=0,min_length=null,max_length=null WHERE locus=OLD.locus;
			ELSE
				SELECT MIN(LENGTH(sequence)),MAX(LENGTH(sequence)),MAX(datestamp) INTO 
				current_min_length,current_max_length,current_datestamp FROM sequences WHERE 
				locus=OLD.locus AND allele_id NOT IN ('0','N','P');
				UPDATE locus_stats SET datestamp=current_datestamp,allele_count=allele_count-1,
				min_length=current_min_length,max_length=current_max_length WHERE locus=OLD.locus;
			END IF;
		ELSIF (TG_OP = 'INSERT' AND NEW.allele_id NOT IN ('0','N','P')) THEN
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

DELETE FROM locus_stats;
INSERT INTO locus_stats(locus,datestamp,allele_count,min_length,max_length) 
SELECT loci.id,MAX(sequences.datestamp),COUNT(sequences.allele_id),MIN(LENGTH(sequence)),MAX(LENGTH(sequence)) 
FROM loci LEFT JOIN sequences ON loci.id=sequences.locus 
WHERE allele_id NOT IN ('N','0','P') OR allele_id IS NULL 
GROUP BY loci.id;
