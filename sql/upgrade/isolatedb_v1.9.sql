CREATE TABLE seqbin_stats (
isolate_id int NOT NULL,
contigs int NOT NULL,
total_length int NOT NULL,
PRIMARY KEY (isolate_id),
CONSTRAINT ss_isolate_id FOREIGN KEY (isolate_id) REFERENCES isolates
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,INSERT,UPDATE,DELETE ON seqbin_stats TO apache;

INSERT INTO seqbin_stats (isolate_id,contigs,total_length) 
SELECT isolate_id,COUNT(id),SUM(length(sequence)) 
FROM sequence_bin GROUP BY isolate_id ORDER BY isolate_id;

CREATE OR REPLACE FUNCTION maint_seqbin_stats() RETURNS TRIGGER AS $maint_seqbin_stats$
	DECLARE
		delta_isolate_id	integer;
		delta_contigs		integer;
		delta_total_length	integer;
	BEGIN
		IF (TG_OP = 'DELETE') THEN
			PERFORM id FROM isolates WHERE id=OLD.isolate_id;
			IF NOT FOUND THEN  --The isolate record itself has been deleted.
				RETURN NULL;
			END IF;
			delta_isolate_id = OLD.isolate_id;
			delta_contigs = - 1;
			delta_total_length = - length(OLD.sequence);		
		ELSIF (TG_OP = 'UPDATE') THEN
			delta_isolate_id = OLD.isolate_id;
			delta_total_length = length(NEW.sequence) - length(OLD.sequence);
			delta_contigs = 0;
		ELSIF (TG_OP = 'INSERT') THEN
			delta_isolate_id = NEW.isolate_id;
			delta_contigs = + 1;
			delta_total_length = + length(NEW.sequence);
		END IF;
		
		<<insert_update>>
		LOOP
			IF (TG_OP = 'DELETE') THEN
				DELETE FROM seqbin_stats WHERE isolate_id = delta_isolate_id AND contigs + delta_contigs = 0;
				EXIT insert_update WHEN found;
			END IF;
			UPDATE seqbin_stats SET contigs = contigs + delta_contigs,total_length = total_length + delta_total_length 
				WHERE isolate_id = delta_isolate_id;
			EXIT insert_update WHEN found;
			INSERT INTO seqbin_stats (isolate_id,contigs,total_length)
				VALUES (delta_isolate_id,delta_contigs,delta_total_length);
			EXIT insert_update;
		END LOOP insert_update;
	
		RETURN NULL;
	END;
$maint_seqbin_stats$ LANGUAGE plpgsql;

CREATE TRIGGER maint_seqbin_stats AFTER INSERT OR UPDATE OR DELETE ON sequence_bin
	FOR EACH ROW
	EXECUTE PROCEDURE maint_seqbin_stats();

	
ALTER TABLE isolates ADD new_version int;
ALTER TABLE isolates ADD CONSTRAINT i_new_version FOREIGN KEY (new_version) REFERENCES isolates(id) 
ON UPDATE NO ACTION ON DELETE NO ACTION;
CREATE INDEX i_i2 ON isolates(new_version);


