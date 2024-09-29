UPDATE db_attributes SET value='49' WHERE field='version';

CREATE OR REPLACE FUNCTION unnest_2d_1d(anyarray)
  RETURNS SETOF anyarray
  LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT AS
$func$
SELECT array_agg($1[d1][d2])
FROM   generate_subscripts($1,1) d1
    ,  generate_subscripts($1,2) d2
GROUP  BY d1
ORDER  BY d1
$func$;


CREATE OR REPLACE FUNCTION get_best_match(
    table_name TEXT,
    primary_key TEXT,
    field_name TEXT,
    query_array TEXT[][],
    min_matches INT DEFAULT 1
)
RETURNS TABLE(profile_id TEXT, profile TEXT[], mismatches int) AS $$
DECLARE
    best_records RECORD;
    min_mismatches INT := array_length(query_array, 1); -- Initialize to the maximum possible mismatches
    current_mismatches INT;
    sql_query TEXT;
    profile_array TEXT[];
    include BOOLEAN;
BEGIN
    -- Create a temporary table to store the results
    CREATE TEMP TABLE temp_results (
        pk TEXT,
        profile TEXT[],
        mismatches INT
    ) ON COMMIT DROP;

    -- The following query returns any profile that has at least min_matches position match with
    -- the query array
    -- sql_query := format('SELECT %I AS pk, %I AS profile FROM %I WHERE (SELECT COUNT(*) FROM unnest_2d_1d($1) WITH ORDINALITY AS sub_array(value,pos) WHERE pos <= array_length(profile::text[],1) AND profile[pos]=ANY(value)) >= ' ||min_matches, primary_key, field_name, table_name, query_array );
    sql_query := format('SELECT %I AS pk, %I AS profile FROM %I', primary_key, field_name, table_name);
    
    RAISE NOTICE '% SQL query: %', clock_timestamp(),sql_query;
    RAISE NOTICE '% Query array: %', clock_timestamp(),query_array;
    
    RAISE NOTICE '% Start loop',clock_timestamp();
    
    FOR best_records IN EXECUTE sql_query USING query_array LOOP
    	include := TRUE;
        -- Fetch the profile array dynamically
        EXECUTE format('SELECT %I FROM %I WHERE %I = $1', field_name, table_name, primary_key) 
        	INTO profile_array USING best_records.pk;

        -- Count mismatches based on position
        current_mismatches := 0;
        <<array_compare>>
        FOR i IN 1 .. array_length(query_array, 1) LOOP
            IF profile_array[i] IS NOT NULL AND query_array[i:i] IS NOT NULL THEN
                IF NOT (profile_array[i]::text = 'N' OR profile_array[i]::text = ANY(query_array[i:i]::text[])) THEN
                     current_mismatches := current_mismatches + 1;
                END IF;
            ELSE
                current_mismatches := current_mismatches + 1;
            END IF;           

            -- Short-circuit if current mismatches exceed the minimum mismatches found so far
            IF current_mismatches > min_mismatches THEN
            	include := FALSE;
                EXIT array_compare;
            END IF;
        END LOOP;

        -- Insert the result into the temporary table
        IF include THEN
 	        INSERT INTO temp_results (pk, profile, mismatches)
	        VALUES (best_records.pk, profile_array, current_mismatches);
	    END IF;
	    

        -- Update min_mismatches if necessary
        IF current_mismatches < min_mismatches THEN
            min_mismatches := current_mismatches;
        END IF;
    END LOOP;
    RAISE NOTICE '% End loop',clock_timestamp();

    -- Return all records with the minimum number of mismatches
    RETURN QUERY
    SELECT t.pk, t.profile, t.mismatches
    FROM temp_results t
    WHERE t.mismatches = min_mismatches;

END;
$$ LANGUAGE plpgsql;

