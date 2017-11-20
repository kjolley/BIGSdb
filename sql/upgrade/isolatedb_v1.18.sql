CREATE TABLE remote_contigs (
seqbin_id bigint NOT NULL UNIQUE,
uri text NOT NULL,
length int,
checksum text,
PRIMARY KEY (seqbin_id),
CONSTRAINT rc_seqbin_id FOREIGN KEY (seqbin_id) REFERENCES sequence_bin (id)
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON remote_contigs TO apache;

--Allow apache user to disable triggers on sequence_bin.
ALTER TABLE sequence_bin OWNER TO apache;

ALTER TABLE sequence_bin ADD remote_contig boolean;
UPDATE sequence_bin SET remote_contig = FALSE;
ALTER TABLE sequence_bin ALTER COLUMN remote_contig SET DEFAULT FALSE;
ALTER TABLE sequence_bin ALTER COLUMN remote_contig SET NOT NULL;
UPDATE sequence_bin SET method=NULL WHERE method='' OR method='unknown';
UPDATE sequence_bin SET original_designation=NULL WHERE original_designation='';
UPDATE sequence_bin SET run_id=NULL WHERE run_id='';
UPDATE sequence_bin SET assembly_id=NULL WHERE assembly_id='';

CREATE OR REPLACE FUNCTION check_sequence_bin() RETURNS TRIGGER AS $check_sequence_bin$
	BEGIN
		IF (length(NEW.sequence) = 0 AND NEW.remote_contig IS FALSE) THEN
			RAISE EXCEPTION 'sequence must be populated if remote_contig is FALSE';
		END IF;
		IF (NEW.remote_contig IS TRUE AND NOT EXISTS(SELECT * FROM remote_contigs WHERE seqbin_id=NEW.id)) THEN
			RAISE EXCEPTION 'Use add_remote_contig() function to add remote contig.';
		END IF;
		RETURN NEW;
	END; 
$check_sequence_bin$ LANGUAGE plpgsql;	

CREATE CONSTRAINT TRIGGER check_sequence_bin AFTER INSERT OR UPDATE ON sequence_bin
	DEFERRABLE
	FOR EACH ROW
	EXECUTE PROCEDURE check_sequence_bin();
	
--Function to populate remote contigs (don't populate both tables manually)
CREATE OR REPLACE FUNCTION add_remote_contig(isolate_id int, sender int, curator int, uri text) 
  RETURNS VOID AS $add_remote_contig$
	DECLARE
		v_id integer;
	BEGIN
		ALTER TABLE sequence_bin DISABLE TRIGGER check_sequence_bin;
		INSERT INTO sequence_bin(isolate_id,remote_contig,sequence,sender,curator,date_entered,datestamp) VALUES
		 (isolate_id,true,'',sender,curator,'now','now') RETURNING id INTO v_id;
		ALTER TABLE sequence_bin ENABLE TRIGGER check_sequence_bin;
		INSERT INTO remote_contigs (seqbin_id,uri) VALUES (v_id,uri);
	END 
$add_remote_contig$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION check_remote_contigs() RETURNS TRIGGER AS $check_remote_contigs$
	DECLARE
		old_length integer;
		new_length integer;
		delta_length integer;
		v_isolate_id integer;
	BEGIN
		IF (TG_OP = 'DELETE') THEN
			IF (EXISTS(SELECT * FROM sequence_bin WHERE (id,remote_contig)=(OLD.seqbin_id,TRUE))) THEN
				RAISE EXCEPTION 'Do not delete directly from remote_contigs table.';
			END IF;	
			IF (OLD.length IS NOT NULL) THEN
				SELECT isolate_id FROM sequence_bin WHERE id=OLD.seqbin_id INTO v_isolate_id;
				UPDATE seqbin_stats SET total_length = total_length - OLD.length WHERE isolate_id = v_isolate_id;
			END IF;
			
		ELSIF (TG_OP = 'UPDATE') THEN
			IF (OLD.length IS NOT NULL) THEN 
				old_length = OLD.length;
			ELSE
				old_length = 0;
			END IF;
			IF (NEW.length IS NOT NULL) THEN 
				new_length = NEW.length;
			ELSE
				new_length = 0;
			END IF;
			delta_length = new_length - old_length;
			IF delta_length != 0 THEN
				SELECT isolate_id FROM sequence_bin WHERE id=OLD.seqbin_id INTO v_isolate_id;
				UPDATE seqbin_stats SET total_length = total_length + delta_length WHERE isolate_id = v_isolate_id;
			END IF;
		ELSIF (TG_OP = 'INSERT') THEN
			IF (EXISTS(SELECT * FROM sequence_bin WHERE id=NEW.seqbin_id AND NOT remote_contig)) THEN
				RAISE EXCEPTION 'Do not insert directly in to remote_contigs table. Use add_remote_contig().';
			END IF;
		END IF;
		RETURN NULL;
	END
$check_remote_contigs$ LANGUAGE plpgsql;

CREATE TRIGGER check_remote_contigs AFTER INSERT OR DELETE OR UPDATE ON remote_contigs
	FOR EACH ROW
	EXECUTE PROCEDURE check_remote_contigs();
	
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
	
		RETURN NULL;
	END;
$maint_seqbin_stats$ LANGUAGE plpgsql;	

CREATE TABLE oauth_credentials (
base_uri text NOT NULL UNIQUE,
consumer_key text NOT NULL,
consumer_secret text NOT NULL,
access_token text,
access_secret text,
session_token text,
session_secret text,
curator int NOT NULL,
date_entered date NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (base_uri),
CONSTRAINT oc_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON oauth_credentials TO apache;

ALTER TABLE private_isolates ADD request_publish boolean DEFAULT false;
UPDATE private_isolates SET request_publish=false;
ALTER TABLE private_isolates ALTER COLUMN request_publish SET NOT NULL;

--This has never been used.
DROP TABLE tag_designations;

