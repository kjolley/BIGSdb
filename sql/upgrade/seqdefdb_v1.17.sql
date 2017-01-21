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
  