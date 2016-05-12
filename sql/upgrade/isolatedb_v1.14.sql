--Standardize all scheme tables to use mv_ prefix.
UPDATE schemes SET dbase_table=REGEXP_REPLACE(dbase_table,'^scheme_','mv_scheme_') WHERE dbase_table IS NOT NULL;

CREATE TABLE scheme_warehouse_indices (
scheme_id int NOT NULL,
locus text NOT NULL,
index int NOT NULL,
PRIMARY KEY (scheme_id,locus),
CONSTRAINT swi_scheme_id FOREIGN KEY (scheme_id) REFERENCES schemes
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT swi_locus FOREIGN KEY (locus) REFERENCES loci
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON scheme_warehouse_indices TO apache;

CREATE OR REPLACE FUNCTION create_isolate_scheme_cache(scheme_id int,view text,temp_table boolean) RETURNS VOID AS $$
	DECLARE
		cache_table text;
		cache_table_temp text;
		scheme_table text;
		fields text[];
		loci text[];
		scheme_locus_count int;
		scheme_info RECORD;
		field_info RECORD;
		scheme_fields text;
		scheme_fields_type text;
		locus_count int;
		qry text;
		allele_count int;
		isolate RECORD;
		table_type text;
	BEGIN
		EXECUTE('SELECT * FROM schemes WHERE id=$1') INTO scheme_info USING scheme_id;
		IF (scheme_info.id IS NULL) THEN
			RAISE EXCEPTION 'Scheme % does not exist.', scheme_id;
		END IF;
		IF temp_table THEN
			table_type:='TEMP TABLE';
		ELSE
			table_type:='TABLE';
		END IF;
		--Create table with a temporary name so we don't nobble cache - rename at end.
		cache_table:='temp_' || view || '_scheme_fields_' || scheme_id;
		cache_table_temp:=cache_table || floor(random()*9999999);
		scheme_table:='temp_scheme_' || scheme_id;
		

		EXECUTE('SELECT ARRAY(SELECT field FROM scheme_fields WHERE scheme_id=$1 ORDER BY primary_key DESC )') 
		INTO fields USING scheme_id;
		scheme_fields:='';
		scheme_fields_type:='';
		
		FOR i IN 1 .. ARRAY_UPPER(fields,1) LOOP
			IF i>1 THEN 
				scheme_fields:=scheme_fields||',';
				scheme_fields_type:=scheme_fields_type||',';
			END IF;
			scheme_fields:=scheme_fields||fields[i];
			EXECUTE('SELECT * FROM scheme_fields WHERE scheme_id=$1 AND field=$2') INTO field_info USING scheme_id,fields[i];
			scheme_fields_type:=scheme_fields_type||fields[i]||' '||field_info.type;
		END LOOP;
		RAISE NOTICE 'Creating temp ad table';
		EXECUTE('CREATE TEMP TABLE ad AS SELECT isolate_id,locus,allele_id FROM allele_designations '
		|| 'WHERE locus IN (SELECT locus FROM scheme_members WHERE scheme_id=$1) AND status!=$2;'
		|| 'CREATE INDEX ON ad(isolate_id,locus)') USING scheme_id,'ignore';
		EXECUTE('SELECT ARRAY(SELECT locus FROM scheme_warehouse_indices WHERE scheme_id=$1 ORDER BY index)') 
		INTO loci USING scheme_id;
		scheme_locus_count:=array_length(loci,1);
			
		IF scheme_info.allow_missing_loci THEN
			--Schemes that allow missing values. Can't do a simple array comparison.
			RAISE NOTICE 'Creating temp_isolates table';
			CREATE TEMP TABLE temp_isolates AS SELECT DISTINCT(isolate_id) AS id FROM ad;
			EXECUTE(FORMAT('CREATE %s %s (id int,%s)',table_type,cache_table_temp,scheme_fields_type));
			qry:=FORMAT('SELECT $1,%s FROM %I WHERE ',scheme_fields,scheme_table);
			FOR i IN 1 .. ARRAY_UPPER(loci,1) LOOP
				IF i>1 THEN
					qry:=qry||' AND ';
				END IF;
				qry:=qry||FORMAT(
				'(profile[%s]=ANY(ARRAY(SELECT allele_id FROM ad WHERE locus=''%s'' AND isolate_id=$1)) OR profile[%s]=''N'')',
				i,replace(loci[i],'''',''''''),i);					
			END LOOP;
			FOR isolate IN SELECT id FROM temp_isolates ORDER BY id LOOP
				RAISE NOTICE '%', isolate.id;
				EXECUTE(FORMAT('INSERT INTO %I (%s)',cache_table_temp,qry)) USING isolate.id;
			END LOOP;	
			DROP TABLE temp_isolates;
		ELSE
			--Complete profile and only one designation per locus
			EXECUTE(FORMAT('CREATE TEMP TABLE temp_isolates AS SELECT id FROM %I JOIN ad ON %I.id=ad.isolate_id '
			|| 'GROUP BY %I.id HAVING COUNT(DISTINCT(locus))=$1 AND COUNT(*)=$1',view,view,view)) USING scheme_locus_count;
			EXECUTE('CREATE TEMP TABLE temp_isolate_profiles AS SELECT id,ARRAY(SELECT ad.allele_id FROM ad '
			|| 'JOIN scheme_warehouse_indices AS sw ON ad.locus=sw.locus AND sw.scheme_id=$1 AND ad.isolate_id=temp_isolates.id '
			|| 'ORDER BY index) AS profile FROM temp_isolates') USING scheme_id;
			EXECUTE(FORMAT('CREATE %s %s AS SELECT id,%s FROM temp_isolate_profiles AS tip JOIN %I AS s ON '
			|| 'tip.profile=s.profile',table_type,cache_table_temp,scheme_fields,scheme_table));
			DROP TABLE temp_isolates;
			DROP TABLE temp_isolate_profiles;
			
			--Profiles with more than one designation at some loci
			EXECUTE(FORMAT('CREATE TEMP TABLE temp_isolates AS SELECT id FROM %I JOIN ad ON %I.id=ad.isolate_id '
			|| 'GROUP BY %I.id HAVING COUNT(DISTINCT(locus))=$1 AND COUNT(*)>$1',view,view,view)) USING scheme_locus_count;
			FOR isolate IN SELECT id FROM temp_isolates LOOP
				qry:=FORMAT('SELECT %s,%s FROM %I WHERE ',isolate.id,scheme_fields,scheme_table);
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
		EXECUTE FORMAT('CREATE INDEX on %I(id)',cache_table_temp);
		FOR i IN 1 .. ARRAY_UPPER(fields,1) LOOP
			EXECUTE FORMAT('CREATE INDEX on %I(%s)',cache_table_temp,fields[i]);
		END LOOP;
		EXECUTE FORMAT('ALTER TABLE %I OWNER TO apache', cache_table_temp);
		IF EXISTS(SELECT * FROM information_schema.tables WHERE table_name=cache_table) THEN
			EXECUTE FORMAT('DROP TABLE %I', cache_table);
		END IF;
		EXECUTE FORMAT('ALTER TABLE %I RENAME TO %s',cache_table_temp,cache_table);
		DROP TABLE ad;
	END;
$$ LANGUAGE plpgsql;

