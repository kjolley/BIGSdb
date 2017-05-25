CREATE OR REPLACE FUNCTION create_scheme_warehouse(i_id int) RETURNS VOID AS $$
	DECLARE
		scheme_table text;
		create_command text;
		pk text;
		x RECORD;
	BEGIN
		scheme_table := 'mv_scheme_' || i_id;
		PERFORM id FROM schemes WHERE id=i_id;
		IF NOT FOUND THEN
			RAISE EXCEPTION 'Scheme % does not exist', i_id;
		END IF;
		PERFORM scheme_id FROM scheme_fields WHERE primary_key AND scheme_id=i_id;
		IF NOT FOUND THEN
			RAISE EXCEPTION 'Scheme % does not have a primary key', i_id;
		END IF;
		IF EXISTS(SELECT * FROM information_schema.tables WHERE table_name=scheme_table) THEN
			EXECUTE FORMAT('DROP TABLE %I', scheme_table);
		END IF;
		PERFORM set_scheme_warehouse_indices(i_id);
		create_command := FORMAT('CREATE TABLE %s (',scheme_table);
		FOR x IN SELECT * FROM scheme_fields WHERE scheme_id=i_id ORDER BY primary_key DESC LOOP
			create_command := FORMAT('%s %s text',create_command, x.field);
			IF x.primary_key THEN
				pk := x.field;
				create_command := create_command || ' NOT NULL';
			END IF;
			create_command := create_command || ',';
		END LOOP;
		EXECUTE FORMAT('%ssender int NOT NULL,curator int NOT NULL,date_entered date NOT NULL,'
		|| 'datestamp date NOT NULL,profile text[], PRIMARY KEY (%s))', 
		create_command, pk);
		FOR x IN SELECT * FROM scheme_fields WHERE scheme_id=i_id ORDER BY primary_key DESC LOOP
			IF x.index THEN
				EXECUTE FORMAT('CREATE INDEX ON %I(UPPER(%s))',scheme_table,x.field);
			END IF;
		END LOOP;
		EXECUTE FORMAT('CREATE UNIQUE INDEX ON %I(md5(profile))',scheme_table);
		EXECUTE FORMAT('CREATE INDEX ON %I ((profile[1]))',scheme_table);
		--We need to be able to drop and recreate as apache user.
		EXECUTE FORMAT('ALTER TABLE %I OWNER TO apache', scheme_table);
	END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION initiate_scheme_warehouse(i_id int)
  RETURNS void AS $$
	DECLARE
		scheme_table text;
		pk text;
		fields text[];
		locus_index int;
		array_length int;
		update_command text;
		x RECORD;
		counter int;
		prev_profile_id text;
	BEGIN
		PERFORM create_scheme_warehouse(i_id);
		scheme_table := 'mv_scheme_' || i_id;
		SELECT field INTO pk FROM scheme_fields WHERE scheme_id=i_id AND primary_key;
		EXECUTE FORMAT(
		'INSERT INTO %I (%s,sender,curator,date_entered,datestamp) '
		|| 'SELECT profile_id,sender,curator,date_entered,datestamp FROM '
		|| 'profiles WHERE scheme_id=%s',scheme_table,pk,i_id);
		FOR x IN SELECT * FROM profile_fields WHERE scheme_id=i_id AND scheme_field NOT IN 
		(SELECT field FROM scheme_fields WHERE scheme_id=i_id AND primary_key) LOOP
			EXECUTE FORMAT('UPDATE %I SET %s=$1 WHERE %s=$2',
			scheme_table,x.scheme_field,pk) USING x.value,x.profile_id;
		END LOOP;

		counter := 0;
		prev_profile_id := '';
		
		--Verifying that profiles are complete
		FOR x IN SELECT profile_id, locus FROM profile_members WHERE scheme_id=i_id ORDER BY profile_id,locus LOOP
			counter := counter + 1;
			IF (prev_profile_id != x.profile_id) THEN
				prev_profile_id = x.profile_id;
				counter := 1;
			END IF;
			SELECT index INTO locus_index FROM scheme_warehouse_indices WHERE scheme_id=i_id AND locus=x.locus;
			IF (locus_index != counter) THEN
				RAISE EXCEPTION 'Profile % is incomplete.', x.profile_id;
			END IF;		
		END LOOP;
		
		--Starting array update
		update_command := format('UPDATE %I SET profile=$1 WHERE %s=$2',scheme_table,pk);
		counter := 0;
		
		FOR x IN SELECT profile_id, array_agg(allele_id ORDER BY locus) AS profile_array FROM profile_members 
		WHERE scheme_id=i_id GROUP BY profile_id ORDER BY profile_id LOOP
			counter := counter + 1;
			EXECUTE update_command USING x.profile_array,x.profile_id;
		END LOOP;
		
		RAISE NOTICE '% profiles cached', counter;		
	END;
$$ LANGUAGE plpgsql; 

--Regenerate scheme caches only for schemes that have indexed text scheme fields as we 
--have changed the index definitions to the upper case values of these fields.
SELECT initiate_scheme_warehouse(scheme_id) FROM scheme_fields WHERE PRIMARY_KEY AND 
scheme_id IN (SELECT scheme_id FROM scheme_members) AND 
scheme_id IN (SELECT scheme_id FROM scheme_fields WHERE type='text' AND index);

ALTER TABLE classification_schemes ADD display_order int;

ALTER TABLE locus_links DROP CONSTRAINT ll_locus;
ALTER TABLE locus_links ADD CONSTRAINT ll_locus FOREIGN KEY(locus) REFERENCES loci 
ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE locus_refs DROP CONSTRAINT lr_locus;
ALTER TABLE locus_refs ADD CONSTRAINT lr_locus FOREIGN KEY(locus) REFERENCES loci 
ON UPDATE CASCADE ON DELETE CASCADE;


