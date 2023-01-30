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
		
		EXECUTE('SELECT ARRAY(SELECT field FROM scheme_fields WHERE scheme_id=$1 ORDER BY field_order,field DESC )') 
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
			 AND status!='ignore'		
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
