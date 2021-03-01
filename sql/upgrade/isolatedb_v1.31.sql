ALTER TABLE seqbin_stats ADD n50 integer;
ALTER TABLE seqbin_stats ADD l50 integer;

CREATE OR REPLACE FUNCTION update_n50(_isolate_id int) RETURNS VOID AS $update_n50$
	DECLARE 
		_lengths integer ARRAY;
		_total integer;
		_n integer;
		_l integer;
		_n50 integer;
		_l50 integer;
	BEGIN
		_lengths := ARRAY(
			SELECT GREATEST(r.length,length(s.sequence)) length FROM sequence_bin s LEFT JOIN remote_contigs r ON s.id=r.seqbin_id WHERE s.isolate_id=_isolate_id ORDER BY length desc
		);
		_n := 0;
		_l := 0;
		SELECT total_length FROM seqbin_stats WHERE isolate_id=_isolate_id INTO _total;
		IF cardinality(_lengths) > 0 THEN
			FOR i IN 1 .. array_upper(_lengths, 1)
	   		LOOP
	   			_n := _n + _lengths[i];
	   			_l := _l + 1;
	   			IF _n >= _total*0.5 THEN
	   				_n50 := _lengths[i];
	   				_l50 := _l;
	   				EXIT;
	   			END IF;
	   		END LOOP;
	   		UPDATE seqbin_stats SET (n50,l50) = (_n50,_l50) WHERE isolate_id=_isolate_id;
--	   		RAISE NOTICE 'id-%: N50: %; L50: %', _isolate_id,_n50,_l50;
	   	END IF;
	END; 
$update_n50$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_n50_all() RETURNS VOID AS $update_n50_all$
	DECLARE
		_ids integer ARRAY;
	BEGIN
		_ids := ARRAY(SELECT isolate_id FROM seqbin_stats ORDER BY isolate_id);
		IF cardinality(_ids) > 0 THEN
			FOR i IN 1 .. array_upper(_ids, 1)
			LOOP
				PERFORM update_n50(_ids[i]);
			END LOOP;
		END IF;
	END; 
$update_n50_all$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION refresh_seqbin_stats() RETURNS VOID AS $refresh_seqbin_stats$
	BEGIN
		RAISE NOTICE 'Updating contig counts and total lengths...';
		DELETE FROM seqbin_stats;
		INSERT INTO seqbin_stats (isolate_id,contigs,total_length) 
			SELECT s.isolate_id,COUNT(s.id),SUM(length(s.sequence)) + SUM(COALESCE(r.length,0)) 
			FROM sequence_bin s LEFT JOIN remote_contigs r ON s.id=r.seqbin_id GROUP BY 
			s.isolate_id ORDER BY s.isolate_id;
		PERFORM update_n50_all();
	END;
$refresh_seqbin_stats$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION maint_seqbin_stats() RETURNS TRIGGER AS $maint_seqbin_stats$
	DECLARE
		delta_isolate_id	 integer;
		delta_contigs		 integer;
		delta_total_length	 integer;
		remote_contig_length integer;
	BEGIN
		IF (TG_OP = 'DELETE') THEN
			PERFORM id FROM isolates WHERE id=OLD.isolate_id;
			IF NOT FOUND THEN  --The isolate record itself has been deleted.
				RETURN NULL;
			END IF;
			delta_isolate_id = OLD.isolate_id;
			delta_contigs = - 1;
			SELECT length FROM remote_contigs WHERE seqbin_id=OLD.id INTO remote_contig_length;	
			IF (remote_contig_length IS NULL) THEN
				remote_contig_length = 0;
			END IF;
			delta_total_length = - length(OLD.sequence) - remote_contig_length;	
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
		PERFORM update_n50(delta_isolate_id);
	
		RETURN NULL;
	END;
$maint_seqbin_stats$ LANGUAGE plpgsql;	

SELECT update_n50_all();
CREATE INDEX ON seqbin_stats(contigs);
CREATE INDEX ON seqbin_stats(total_length);
CREATE INDEX ON seqbin_stats(n50);
CREATE INDEX ON seqbin_stats(l50);

DROP TABLE experiment_sequences;
DROP TABLE experiments;

CREATE TABLE analysis_results (
name text NOT NULL,
isolate_id integer NOT NULL,
datestamp date NOT NULL DEFAULT now(),
results jsonb NOT NULL,
PRIMARY KEY(name,isolate_id),
CONSTRAINT ar_isolate_id FOREIGN KEY (isolate_id) REFERENCES isolates
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON analysis_results TO apache;

CREATE TABLE genome_submission_stats (
submission_id text NOT NULL,
index int NOT NULL,
contigs integer NOT NULL,
total_length integer NOT NULL,
n50 integer NOT NULL,
PRIMARY KEY(submission_id,index),
CONSTRAINT isi_submission_id FOREIGN KEY (submission_id) REFERENCES submissions
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON genome_submission_stats TO apache;
