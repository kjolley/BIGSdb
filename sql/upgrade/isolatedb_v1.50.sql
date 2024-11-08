UPDATE db_attributes SET value='50' WHERE field='version';

CREATE TABLE analysis_fields (
analysis_name text NOT NULL,
field_name text NOT NULL,
analysis_display_name text,
field_description text,
json_path text NOT NULL,
data_type text NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (analysis_name,field_name),
UNIQUE(analysis_name,json_path),
CONSTRAINT af_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);
GRANT SELECT,UPDATE,INSERT,DELETE ON analysis_fields TO apache;

CREATE TABLE analysis_results_cache (
    isolate_id int NOT NULL,
    analysis_name text NOT NULL,
    json_path text NOT NULL,
    value text NOT NULL,
--  No primary key defined - there may be multiple values for some fields.
    CONSTRAINT arc_analysis_name_json_path FOREIGN KEY (analysis_name,json_path) REFERENCES 
    	analysis_fields(analysis_name,json_path)
    ON DELETE CASCADE
    ON UPDATE CASCADE
);
CREATE INDEX ON analysis_results_cache(analysis_name,json_path,value);
GRANT SELECT,UPDATE,INSERT,DELETE ON analysis_results_cache TO apache;


CREATE OR REPLACE FUNCTION normalize_analysis_jsonb(isolate_id int,name text,json_data jsonb,_jsonpath text DEFAULT NULL)
RETURNS VOID AS $$
DECLARE
    field RECORD;
    val text;
BEGIN
	IF _jsonpath IS NOT NULL THEN
		BEGIN
            FOR val IN SELECT jsonb_path_query(json_data, _jsonpath::jsonpath)
            LOOP
                INSERT INTO analysis_results_cache(isolate_id, analysis_name, json_path, value)
                VALUES (isolate_id, name, _jsonpath, trim(both '"' FROM val::text));
            END LOOP;
        EXCEPTION
            WHEN others THEN
                RAISE NOTICE 'Invalid JSONPath: %', _jsonpath;
        END;       
	ELSE
         FOR field IN SELECT json_path FROM analysis_fields WHERE analysis_name = name
        LOOP
            BEGIN
                -- Extract the values using the JSONPath
                FOR val IN SELECT jsonb_path_query(json_data, field.json_path::jsonpath)
                LOOP
                    IF val IS NOT NULL THEN
                        INSERT INTO analysis_results_cache(isolate_id, analysis_name, json_path, value)
                        VALUES (isolate_id, name, field.json_path, trim(both '"' FROM val::text));
                    END IF;
                END LOOP;
            EXCEPTION
                WHEN others THEN
                    RAISE NOTICE 'Invalid JSONPath: %', field.json_path;
            END;
        END LOOP;
	END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trigger_normalize_analysis_jsonb()
RETURNS TRIGGER AS $$
BEGIN
    -- Delete existing cache for the isolate_id
    DELETE FROM analysis_results_cache WHERE (isolate_id,analysis_name)=(NEW.isolate_id,NEW.name);

    -- Call the normalization function to process JSONB data
    PERFORM normalize_analysis_jsonb(NEW.isolate_id,NEW.name,NEW.results);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_analysis_cache
AFTER INSERT OR UPDATE OF results
ON analysis_results
FOR EACH ROW
EXECUTE FUNCTION trigger_normalize_analysis_jsonb();

CREATE OR REPLACE FUNCTION delete_analysis_cache_value()
RETURNS TRIGGER AS $$
BEGIN
	DELETE FROM analysis_results_cache WHERE (isolate_id,analysis_name)=(OLD.isolate_id,OLD.name);
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER delete_analysis_cache_value
AFTER DELETE 
ON analysis_results
FOR EACH ROW
EXECUTE FUNCTION delete_analysis_cache_value();

CREATE OR REPLACE FUNCTION insert_cache_on_new_analysis_field()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM normalize_analysis_jsonb(isolate_id,name,results,NEW.json_path)
    FROM analysis_results ar
    WHERE ar.name = NEW.analysis_name;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER insert_cache_on_new_analysis_field
AFTER INSERT
ON analysis_fields
FOR EACH ROW
EXECUTE FUNCTION insert_cache_on_new_analysis_field();

CREATE OR REPLACE FUNCTION update_cache_on_changed_analysis_field()
RETURNS TRIGGER AS $$
BEGIN
	-- We use NEW.json_path below because this will have cascade updated if it changed.
	DELETE FROM analysis_results_cache WHERE (analysis_name,json_path)=(OLD.analysis_name,NEW.json_path);

    PERFORM normalize_analysis_jsonb(isolate_id,name,results,NEW.json_path)
    FROM analysis_results ar
    WHERE ar.name = NEW.analysis_name;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_cache_on_changed_analysis_field
AFTER UPDATE
ON analysis_fields
FOR EACH ROW
EXECUTE FUNCTION update_cache_on_changed_analysis_field();

CREATE OR REPLACE FUNCTION refresh_analysis_cache()
RETURNS VOID AS $$
DECLARE
	af RECORD;
BEGIN
	DELETE FROM analysis_results_cache;
	FOR af IN SELECT DISTINCT(analysis_name) FROM analysis_fields ar
	LOOP
		PERFORM normalize_analysis_jsonb(isolate_id,af.analysis_name,results)
	    FROM analysis_results;
	END LOOP;
END;
$$ LANGUAGE plpgsql;

