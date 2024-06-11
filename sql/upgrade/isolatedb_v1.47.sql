UPDATE db_attributes SET value='47' WHERE field='version';

ALTER TABLE schemes ADD quality_metric_count_zero boolean DEFAULT FALSE;
UPDATE schemes SET quality_metric_count_zero=FALSE;
ALTER TABLE schemes ALTER COLUMN quality_metric_count_zero SET NOT NULL;
ALTER TABLE private_isolates ADD embargo date;

CREATE OR REPLACE FUNCTION create_isolate_scheme_status_table(_scheme_id int,_view text,_temp_table boolean,_method text DEFAULT 'full') 
RETURNS VOID AS $$
	--_method param:
	--full (default): Recreate full cache.
	--incremental:    Only add to the cache, do not replace existing values. If cache does not already exist, a
	--                full refresh will be performed.
	--daily:          Add cache for isolates updated today.
	--daily_replace:  Replace cache for isolates updated today.
	DECLARE
		cache_table text;
		cache_table_temp text;
		scheme_info RECORD;
		modify_qry text;
		table_type text;
	BEGIN
		EXECUTE('SELECT * FROM schemes WHERE id=$1') INTO scheme_info USING _scheme_id;
		IF (scheme_info.id IS NULL) THEN
			RAISE EXCEPTION 'Scheme % does not exist.', _scheme_id;
		END IF;
		IF _temp_table THEN
			table_type:='TEMP TABLE';
		ELSE
			table_type:='TABLE';
		END IF;
		IF _method NOT IN ('full','incremental','daily','daily_replace') THEN
			RAISE EXCEPTION 'Unrecognized method.';
		END IF;
		IF _method != 'full' AND _temp_table THEN
			RAISE EXCEPTION 'You cannot do an incremental update on a temporary table.';
		END IF;
		--Create table with a temporary name so we don't nobble cache - rename at end.
		cache_table:='temp_' || _view || '_scheme_completion_' || _scheme_id;
		IF EXISTS(SELECT * FROM information_schema.tables WHERE table_name=cache_table) THEN
			IF _method='daily_replace' THEN
				EXECUTE(FORMAT('DELETE FROM %I WHERE id IN (SELECT id FROM %I WHERE datestamp=''today'')',cache_table,_view));
			END IF;
		ELSE
			_method='full';
		END IF;
		cache_table_temp:=cache_table || floor(random()*9999999);

		IF _method='incremental' THEN
			modify_qry:=FORMAT(' AND isolate_id NOT IN (SELECT id FROM %I) ',cache_table);
		ELSIF _method='daily' OR _method='daily_replace' THEN
			modify_qry:=FORMAT(' AND isolate_id NOT IN (SELECT id FROM %I) AND isolate_id IN (SELECT id FROM %I WHERE datestamp=''today'') ',
			cache_table,_view);
		ELSE
			modify_qry:=' ';
		END IF;
		IF scheme_info.quality_metric_count_zero IS FALSE THEN
			modify_qry:='AND allele_id <> ''0''';
		END IF;
		EXECUTE('CREATE TEMP TABLE ad AS SELECT isolate_id,locus,allele_id FROM allele_designations '
		|| 'WHERE locus IN (SELECT locus FROM scheme_members WHERE scheme_id=$1)'||modify_qry
		|| ';CREATE INDEX ON ad(isolate_id,locus)') USING _scheme_id;
		EXECUTE(FORMAT('CREATE %s %s AS SELECT %I.id, COUNT(DISTINCT locus) AS locus_count FROM %I JOIN ad '
		||'ON %I.id=ad.isolate_id AND locus IN (SELECT locus FROM scheme_members WHERE scheme_id=%s) GROUP BY %I.id;'
	  	,table_type,cache_table_temp,_view,_view,_view,_scheme_id,_view));

		IF _method != 'full' THEN
			EXECUTE(FORMAT('INSERT INTO %I (SELECT * FROM %I)',cache_table_temp,cache_table)); 
		END IF;
		EXECUTE FORMAT('CREATE INDEX on %I(id)',cache_table_temp);
		EXECUTE FORMAT('CREATE INDEX ON %I(locus_count)',cache_table_temp);
		EXECUTE FORMAT('ALTER TABLE %I OWNER TO apache', cache_table_temp);
		IF EXISTS(SELECT * FROM information_schema.tables WHERE table_name=cache_table) THEN
			EXECUTE FORMAT('DROP TABLE %I', cache_table);
		END IF;
		EXECUTE FORMAT('ALTER TABLE %I RENAME TO %s',cache_table_temp,cache_table);
		DROP TABLE ad;
	END;
$$ LANGUAGE plpgsql;

CREATE TABLE embargo_history (
isolate_id int NOT NULL,
timestamp timestamp NOT NULL,
action text NOT NULL,
embargo date,
curator int NOT NULL,
PRIMARY KEY(isolate_id, timestamp),
CONSTRAINT eh_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE,
CONSTRAINT eh_isolate FOREIGN KEY (isolate_id) REFERENCES isolates
ON DELETE CASCADE
ON UPDATE CASCADE
);

CREATE INDEX ON embargo_history USING brin(timestamp);
GRANT SELECT,UPDATE,INSERT,DELETE ON embargo_history TO apache;
