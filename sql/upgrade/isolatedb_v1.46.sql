UPDATE db_attributes SET value='46' WHERE field='version';

ALTER TABLE query_interface_fields ADD CONSTRAINT qif_id FOREIGN KEY (id) REFERENCES query_interfaces(id) 
ON DELETE CASCADE
ON UPDATE CASCADE;

CREATE INDEX i_i_date_entered ON isolates(date_entered);

--The temp_isolates_scheme_completion_X cache tables should have a primary key.
--Any new ones created now will have one, but old ones did not and may never 
--get recreated. The following will add them. If there is a conflict then the 
--table will be dropped - it will be recreated the next time the cache is 
--renewed.

CREATE OR REPLACE FUNCTION add_completion_cache_pks() RETURNS void AS $$
DECLARE
    cache_table text;
BEGIN
    FOR cache_table IN (
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name ~ '^temp_isolates_scheme_completion_\d+$'
    )
    LOOP
    	BEGIN
	        IF NOT EXISTS (
	            SELECT 1
	            FROM pg_constraint
	            WHERE conrelid = cache_table::regclass
	            AND contype = 'p'
	        ) THEN
	        	RAISE NOTICE 'Adding primary key to table %', cache_table;
	            EXECUTE format('ALTER TABLE %I ADD PRIMARY KEY (id);', cache_table);
	            RAISE NOTICE 'Removing old index %', cache_table || '_id_idx';
	            EXECUTE format('DROP INDEX IF EXISTS %I;', cache_table || '_id_idx');
	        END IF;
	        EXCEPTION WHEN unique_violation THEN
	        	RAISE NOTICE 'Cannot add PK to table %. Dropping table - it will recreate when cache is renewed.', cache_table;
	        	EXECUTE format('DROP TABLE %I;', cache_table);
        END;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

SELECT add_completion_cache_pks();

DROP FUNCTION add_completion_cache_pks();

CREATE INDEX ON history USING brin(timestamp);
