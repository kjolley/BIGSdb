UPDATE db_attributes SET value='55' WHERE field='version';

ALTER TABLE seqbin_stats ADD COLUMN methods text[] NOT NULL DEFAULT '{}';

UPDATE seqbin_stats st SET methods=m.methods
FROM (
	SELECT isolate_id,
		COALESCE(
			array_agg(DISTINCT method ORDER BY method) FILTER (WHERE method IS NOT NULL),
			ARRAY[]::text[]) AS methods
	FROM sequence_bin
	GROUP BY isolate_id
) m
WHERE st.isolate_id=m.isolate_id;

CREATE INDEX seqbin_stats_methods_idx ON seqbin_stats USING GIN(methods);

CREATE OR REPLACE FUNCTION refresh_seqbin_stats() RETURNS VOID AS $refresh_seqbin_stats$
	BEGIN
		RAISE NOTICE 'Updating contig counts and total lengths...';
		DELETE FROM seqbin_stats;
		INSERT INTO seqbin_stats (isolate_id,contigs,total_length,methods)
			SELECT s.isolate_id,COUNT(s.id),SUM(length(s.sequence)) + SUM(COALESCE(r.length,0)),
				COALESCE(
					array_agg(DISTINCT s.method ORDER BY s.method) FILTER (WHERE s.method IS NOT NULL),
					ARRAY[]::text[])
			FROM sequence_bin s LEFT JOIN remote_contigs r ON s.id=r.seqbin_id
			GROUP BY s.isolate_id ORDER BY s.isolate_id;
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
			IF NOT FOUND THEN
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
			UPDATE seqbin_stats SET
				contigs = contigs + delta_contigs,
				total_length = total_length + delta_total_length
				WHERE isolate_id = delta_isolate_id;
			EXIT insert_update WHEN found;
			INSERT INTO seqbin_stats (isolate_id,contigs,total_length)
				VALUES (delta_isolate_id,delta_contigs,delta_total_length);
			EXIT insert_update;
		END LOOP insert_update;

		IF (TG_OP = 'INSERT'
			OR TG_OP = 'DELETE'
			OR (TG_OP = 'UPDATE' AND OLD.method IS DISTINCT FROM NEW.method)) THEN
			IF EXISTS (SELECT 1 FROM seqbin_stats WHERE isolate_id=delta_isolate_id) THEN
				UPDATE seqbin_stats SET methods =
					COALESCE(
						(SELECT array_agg(DISTINCT method ORDER BY method)
						 FROM sequence_bin
						 WHERE isolate_id=delta_isolate_id AND method IS NOT NULL),
						ARRAY[]::text[])
					WHERE isolate_id=delta_isolate_id;
			END IF;
		END IF;

		RETURN NULL;
	END;
$maint_seqbin_stats$ LANGUAGE plpgsql;
