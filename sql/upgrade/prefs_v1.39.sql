CREATE OR REPLACE FUNCTION name_dashboard() RETURNS TRIGGER AS $next_dashboard$
DECLARE	
	dashboard_count integer;
	new_name text;
	name_exists boolean;
BEGIN
    IF NEW.name IS NULL THEN
    	dashboard_count := 1;
    	name_exists := 1;
    	WHILE name_exists LOOP
    		new_name := 'dashboard#' || LPAD((dashboard_count)::text,2,'0');
    		IF NOT EXISTS (SELECT * FROM dashboards WHERE (guid,dbase_config,name)=(NEW.guid,NEW.dbase_config,new_name)) THEN
    			name_exists = false;
    		END IF;
    		dashboard_count := dashboard_count + 1;
    	END LOOP;
    	NEW.name := new_name;  	
    END IF;
    RETURN NEW;
END;
$next_dashboard$ language plpgsql;
