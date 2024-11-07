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
--    PRIMARY KEY(isolate_id, analysis_name, json_path),
    CONSTRAINT arc_analysis_name_json_path FOREIGN KEY (analysis_name,json_path) REFERENCES 
    	analysis_fields(analysis_name,json_path)
    ON DELETE CASCADE
    ON UPDATE CASCADE
);
CREATE INDEX ON analysis_results_cache(analysis_name,json_path,value);
GRANT SELECT,UPDATE,INSERT,DELETE ON analysis_results_cache TO apache;


CREATE OR REPLACE FUNCTION normalize_analysis_jsonb(isolate_id int,name text,json_data jsonb)
RETURNS VOID AS $$
DECLARE
    field RECORD;
    val text;
BEGIN
    -- Iterate over each defined path in the analysis_fields table
    FOR field IN SELECT json_path FROM analysis_fields WHERE analysis_name=name
    LOOP
        -- Extract the value using the JSONPath
 		SELECT jsonb_path_query(json_data,field.json_path::jsonpath) INTO val;
        -- Insert the key-value pair into the cache table if the value is not null
        IF val IS NOT NULL THEN
            INSERT INTO analysis_results_cache(isolate_id, analysis_name, json_path, value)
            VALUES (isolate_id, name, field.json_path, trim(both '"' FROM val));
        END IF;
    END LOOP;
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

CREATE OR REPLACE FUNCTION update_cache_on_analysis_fields_change()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM normalize_analysis_jsonb(isolate_id,name,results)
    FROM analysis_results ar
    WHERE ar.name = NEW.analysis_name;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_cache_on_analysis_fields
AFTER INSERT OR UPDATE
ON analysis_fields
FOR EACH ROW
EXECUTE FUNCTION update_cache_on_analysis_fields_change();

