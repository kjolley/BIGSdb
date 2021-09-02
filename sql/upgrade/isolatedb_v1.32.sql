CREATE OR REPLACE FUNCTION trg_seqbin_stats_after_change_1()
    RETURNS trigger AS
$BODY$    
BEGIN
 -- We only want the following to run once per transaction per isolate
 -- Not on addition of each contig.
	PERFORM update_n50(NEW.isolate_id);
	DELETE FROM last_run WHERE isolate_id=NEW.isolate_id;
	DELETE FROM analysis_results WHERE isolate_id=NEW.isolate_id;
	RETURN NULL; 
END;
$BODY$ LANGUAGE plpgsql;
