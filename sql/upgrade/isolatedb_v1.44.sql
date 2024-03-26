--Never-used indexes.
DROP INDEX seqbin_stats_l50_idx;	--seqbin_stats(l50)
DROP INDEX i_eavi1;					--eav_int(field,value)
DROP INDEX i_eavt1;					--eav_text(field,value)
DROP INDEX i_eavb1;					--eav_boolean(field,value)
DROP INDEX i_eavd1;					--eav_date(field,value)
DROP INDEX i_eavf1;					--eav_float(field,value)

--Rarely used scans with high writes
DROP INDEX i_ad4;					--allele_designations(datestamp)
DROP INDEX i_as2;					--allele_sequences(datestamp)
DROP INDEX seqbin_stats_n50_idx;	--seqbin_stats(n50)

--The option to set allele_designations to 'ignore' has been removed.
DELETE FROM allele_designations WHERE status='ignore';

CREATE OR REPLACE FUNCTION create_isolate_scheme_cache(_scheme_id int,_view text,_temp_table boolean,_method text DEFAULT 'full') 
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
		scheme_table text;
		fields text[];
		loci text[];
		scheme_locus_count int;
		scheme_info RECORD;
		scheme_fields text;
		unqual_scheme_fields text;
		isolate_qry text;
		modify_qry text;
		qry text;
		isolate RECORD;
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
		cache_table:='temp_' || _view || '_scheme_fields_' || _scheme_id;
		IF EXISTS(SELECT * FROM information_schema.tables WHERE table_name=cache_table) THEN
			IF _method='daily_replace' THEN
				EXECUTE(FORMAT('DELETE FROM %I WHERE id IN (SELECT id FROM %I WHERE datestamp=''today'')',cache_table,_view));
			END IF;
		ELSE
			_method:='full';
		END IF;
		cache_table_temp:=cache_table || floor(random()*9999999);
		scheme_table:='temp_scheme_' || _scheme_id;

		EXECUTE('SELECT ARRAY(SELECT field FROM scheme_fields WHERE scheme_id=$1 ORDER BY primary_key DESC )') 
		INTO fields USING _scheme_id;
		IF ARRAY_UPPER(fields,1) IS NULL THEN
			RAISE EXCEPTION 'Scheme has no fields.';
		END IF;
		scheme_fields:='';
		unqual_scheme_fields:='';
		
		FOR i IN 1 .. ARRAY_UPPER(fields,1) LOOP
			IF i>1 THEN 
				scheme_fields:=scheme_fields||',';
				unqual_scheme_fields:=unqual_scheme_fields||',';
			END IF;
			scheme_fields:=scheme_fields||'st.'||fields[i];
			unqual_scheme_fields:=unqual_scheme_fields||fields[i];
		END LOOP;
		IF _method='incremental' THEN
			EXECUTE(FORMAT('CREATE TEMP TABLE to_update AS SELECT v.id FROM %I v LEFT JOIN %I c ON v.id=c.id '
			|| 'WHERE c.id IS NULL',_view,cache_table));
			modify_qry:=' AND isolate_id IN (SELECT id FROM to_update) ';			
		ELSIF _method='daily' OR _method='daily_replace' THEN
			EXECUTE(FORMAT('CREATE TEMP TABLE to_update AS SELECT v.id FROM %I v LEFT JOIN %I c ON v.id=c.id '
			|| 'WHERE c.id IS NULL AND v.datestamp=''today''',_view, cache_table));
			modify_qry:=' AND isolate_id IN (SELECT id FROM to_update) ';
		ELSE
			modify_qry:=' ';
		END IF;
		EXECUTE('CREATE TEMP TABLE ad AS SELECT isolate_id,locus,allele_id FROM allele_designations '
		|| 'WHERE locus IN (SELECT locus FROM scheme_members WHERE scheme_id=$1)'||modify_qry
		|| ';CREATE INDEX ON ad(isolate_id,locus)') USING _scheme_id;
		EXECUTE('SELECT ARRAY(SELECT locus FROM scheme_warehouse_indices WHERE scheme_id=$1 ORDER BY index)') 
		INTO loci USING _scheme_id;
		scheme_locus_count:=array_length(loci,1);
		modify_qry=regexp_replace(modify_qry,'^ AND',' WHERE');
			
		IF scheme_info.allow_missing_loci THEN
			--Schemes that allow missing values. Can't do a simple array comparison.
			isolate_qry:='CREATE TEMP TABLE temp_isolates AS SELECT DISTINCT(isolate_id) AS id FROM ad' || modify_qry;
			EXECUTE(isolate_qry);
			qry:=FORMAT('CREATE %s %s AS SELECT ti.id,%s FROM temp_isolates AS ti JOIN ad ON ti.id=ad.isolate_id JOIN %I AS st ON ',
			table_type,cache_table_temp,scheme_fields,scheme_table);
			FOR i IN 1 .. ARRAY_UPPER(loci,1) LOOP
				IF i>1 THEN
					qry:=qry||' AND ';
				END IF;
				qry:=qry||FORMAT(
				'(profile[%s]=ANY(array_append(ARRAY(SELECT allele_id FROM ad WHERE locus=''%s'' AND isolate_id=ti.id),''N'')))',
				i,replace(loci[i],'''',''''''));					
			END LOOP;
			qry:=qry||FORMAT(' GROUP BY ti.id,%s',scheme_fields);
			EXECUTE qry;	
			DROP TABLE temp_isolates;
		ELSE
			--Complete profile and only one designation per locus
			isolate_qry=FORMAT('CREATE TEMP TABLE temp_isolates AS SELECT id FROM %I JOIN ad ON %I.id=ad.isolate_id%s',_view,_view,modify_qry);
			isolate_qry:=isolate_qry||FORMAT('GROUP BY %I.id HAVING COUNT(DISTINCT(locus))=$1 AND COUNT(*)=$1',_view);
			EXECUTE(isolate_qry) USING scheme_locus_count;
			EXECUTE('CREATE TEMP TABLE temp_isolate_profiles AS SELECT id,ARRAY(SELECT ad.allele_id FROM ad '
			|| 'JOIN scheme_warehouse_indices AS sw ON ad.locus=sw.locus AND sw.scheme_id=$1 AND ad.isolate_id=temp_isolates.id '
			|| 'ORDER BY index) AS profile FROM temp_isolates') USING _scheme_id;
			EXECUTE(FORMAT('CREATE %s %s AS SELECT id,%s FROM temp_isolate_profiles AS tip JOIN %I AS st ON '
			|| 'tip.profile=st.profile',table_type,cache_table_temp,scheme_fields,scheme_table));
			DROP TABLE temp_isolates;
			DROP TABLE temp_isolate_profiles;
			
			--Profiles with more than one designation at some loci
			EXECUTE(FORMAT('CREATE TEMP TABLE temp_isolates AS SELECT id FROM %I JOIN ad ON %I.id=ad.isolate_id '
			|| '%sGROUP BY %I.id HAVING COUNT(DISTINCT(locus))=$1 AND COUNT(*)>$1',_view,_view,modify_qry,_view)) USING scheme_locus_count;
			FOR isolate IN SELECT id FROM temp_isolates LOOP
				qry:=FORMAT('SELECT %s,%s FROM %I AS st WHERE ',isolate.id,scheme_fields,scheme_table);
				FOR i IN 1 .. ARRAY_UPPER(loci,1) LOOP
					IF i>1 THEN
						qry:=qry||' AND ';
					END IF;
					qry:=qry||FORMAT('profile[%s]=ANY(ARRAY(SELECT allele_id FROM ad WHERE locus=''%s'' AND isolate_id=%s))',
					i,replace(loci[i],'''',''''''),isolate.id);					
				END LOOP;
				EXECUTE(FORMAT('INSERT INTO %I (%s)',cache_table_temp,qry));
			END LOOP;			
			DROP TABLE temp_isolates;
		END IF;
		IF _method != 'full' THEN
			EXECUTE(FORMAT('INSERT INTO %I (SELECT id,%s FROM %I)',cache_table_temp,unqual_scheme_fields,cache_table)); 
		END IF;
		EXECUTE FORMAT('CREATE INDEX on %I(id)',cache_table_temp);
		FOR i IN 1 .. ARRAY_UPPER(fields,1) LOOP
			EXECUTE FORMAT('CREATE INDEX on %I(%s)',cache_table_temp,fields[i]);
		END LOOP;
		EXECUTE FORMAT('ALTER TABLE %I OWNER TO apache', cache_table_temp);
		IF EXISTS(SELECT * FROM information_schema.tables WHERE table_name=cache_table) THEN
			EXECUTE FORMAT('DROP TABLE %I', cache_table);
		END IF;
		IF EXISTS(SELECT * FROM information_schema.tables WHERE table_name='to_update') THEN
			EXECUTE('DROP TABLE to_update');
		END IF;
		EXECUTE FORMAT('ALTER TABLE %I RENAME TO %s',cache_table_temp,cache_table);
		DROP TABLE ad;
	END;
$$ LANGUAGE plpgsql;

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

CREATE OR REPLACE FUNCTION get_isolate_scheme_fields(_isolate_id int,_scheme_id int) 
RETURNS SETOF record AS $$
	--This assumes that a scheme cache table exists (e.g. temp_scheme_1) and is up-to-date.
	--This will be the case during cache renewal since this table is created as the first
	--step in this.
	DECLARE
 		scheme_table text;
		fields text[];
 		scheme_info RECORD;
 		loci text[];
 		scheme_fields text;
 		designation text;
 		qry text;
 		max_missing int;
 		missing int := 0;
 		is_missing boolean;

	BEGIN
		EXECUTE('SELECT * FROM schemes WHERE id=$1') INTO scheme_info USING _scheme_id;
		IF (scheme_info.id IS NULL) THEN
			RAISE EXCEPTION 'Scheme % does not exist.', _scheme_id;
		END IF;

		scheme_table:='temp_scheme_' || _scheme_id;
		
		IF NOT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=scheme_table) THEN
			RAISE EXCEPTION 'Scheme cache table % does not exist.', scheme_table;
		END IF;
		
		EXECUTE('SELECT ARRAY(SELECT field FROM scheme_fields WHERE scheme_id=$1 ORDER BY field_order,field)') 
		INTO fields USING _scheme_id;
		IF ARRAY_UPPER(fields,1) IS NULL THEN
			RAISE EXCEPTION 'Scheme has no fields.';
		END IF;
		
		scheme_fields:='';
		
		FOR i IN 1 .. ARRAY_UPPER(fields,1) LOOP
			IF i>1 THEN 
				scheme_fields:=scheme_fields||',';
			END IF;
			scheme_fields:=scheme_fields||fields[i];
		END LOOP;
		
		EXECUTE(FORMAT('SELECT max(missing_loci) FROM %I',scheme_table)) INTO max_missing;
		
		EXECUTE('SELECT ARRAY(SELECT locus FROM scheme_warehouse_indices WHERE scheme_id=$1 ORDER BY index)') 
		INTO loci USING _scheme_id;

		qry:=FORMAT('SELECT %s FROM %I WHERE ',scheme_fields,scheme_table);
	
		FOR i in 1 .. ARRAY_UPPER(loci,1) LOOP
			IF i>1 THEN
				qry:=qry || ' AND ';
			END IF;
			qry:=qry || 'profile[' || i || '] IN (''N''';
			is_missing:=TRUE;
			FOR designation IN SELECT allele_id FROM allele_designations WHERE (isolate_id,locus)=(_isolate_id,loci[i])			
			LOOP
				is_missing:=FALSE;
				designation=REPLACE(designation,'''','''''');
				qry:=qry || ',''' || designation || '''';
			END LOOP;
			qry:=qry || ')';
			IF (is_missing) THEN
				missing:=missing+1;
			END IF;
			IF (missing > max_missing) THEN
				RETURN;
			END IF;
		END LOOP;
		RETURN QUERY EXECUTE qry;	
 	END;
$$ LANGUAGE plpgsql;

