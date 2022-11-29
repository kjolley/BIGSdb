CREATE TABLE guid (
guid text NOT NULL,
last_accessed date NOT NULL,
PRIMARY KEY (guid)
);

CREATE TABLE general (
guid text NOT NULL,
dbase text NOT NULL,
attribute text NOT NULL,
value text NOT NULL,
PRIMARY KEY (guid,dbase,attribute),
CONSTRAINT conguid FOREIGN KEY (guid) REFERENCES guid
ON DELETE CASCADE
ON UPDATE CASCADE
);

CREATE TABLE locus (
guid text NOT NULL,
dbase text NOT NULL,
locus text NOT NULL,
action text NOT NULL,
value text NOT NULL,
PRIMARY KEY (guid,dbase,locus,action),
CONSTRAINT conguid FOREIGN KEY (guid) REFERENCES guid
ON DELETE CASCADE
ON UPDATE CASCADE
);

CREATE TABLE scheme (
guid text NOT NULL,
dbase text NOT NULL,
scheme_id int NOT NULL,
action text NOT NULL,
value boolean NOT NULL,
PRIMARY KEY (guid,dbase,scheme_id,action),
CONSTRAINT conguid FOREIGN KEY (guid) REFERENCES guid
ON DELETE CASCADE
ON UPDATE CASCADE
);

CREATE TABLE scheme_field (
guid text NOT NULL,
dbase text NOT NULL,
scheme_id int NOT NULL,
field text NOT NULL,
action text NOT NULL,
value boolean NOT NULL,
PRIMARY KEY (guid,dbase,scheme_id,field,action),
CONSTRAINT conguid FOREIGN KEY (guid) REFERENCES guid
ON DELETE CASCADE
ON UPDATE CASCADE
);

CREATE TABLE field (
guid text NOT NULL,
dbase text NOT NULL,
field text NOT NULL,
action text NOT NULL,
value boolean NOT NULL,
PRIMARY KEY (guid,dbase,field,action),
CONSTRAINT conguid FOREIGN KEY (guid) REFERENCES guid
ON DELETE CASCADE
ON UPDATE CASCADE
);

CREATE TABLE plugin (
guid text NOT NULL,
dbase text NOT NULL,
plugin text NOT NULL,
attribute text NOT NULL,
value text NOT NULL,
PRIMARY KEY (guid,dbase,plugin,attribute),
CONSTRAINT conguid FOREIGN KEY (guid) REFERENCES guid
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON guid,general,locus,scheme,scheme_field,field,plugin TO apache;

CREATE TABLE dashboards (
id bigserial NOT NULL UNIQUE, 
guid text NOT NULL,
dbase_config text NOT NULL,
name text NOT NULL,
data jsonb NOT NULL,
UNIQUE (guid,dbase_config,name),
PRIMARY KEY (id),
FOREIGN KEY (guid) REFERENCES guid
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON dashboards TO apache;
GRANT USAGE,SELECT ON SEQUENCE dashboards_id_seq TO apache;

CREATE OR REPLACE FUNCTION next_dashboard(_guid text,_dbase_config text) RETURNS text AS $next_dashboard$
DECLARE
		dashboard_count integer;
BEGIN
	SELECT COUNT(*) INTO dashboard_count FROM dashboards WHERE (guid,dbase_config)=(_guid,_dbase_config);
	RETURN 'dashboard#' || (dashboard_count+1);
END
$next_dashboard$ LANGUAGE plpgsql;

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

CREATE TRIGGER trig_insert_dashboards
BEFORE INSERT
ON dashboards
FOR EACH ROW
EXECUTE PROCEDURE name_dashboard();

CREATE TABLE active_dashboards (
guid text NOT NULL,
dbase_config text NOT NULL,
id bigint NOT NULL,
type text NOT NULL,
value text NOT NULL,
PRIMARY KEY(guid,dbase_config,type,value),
FOREIGN KEY (id) REFERENCES dashboards
ON DELETE CASCADE
ON UPDATE CASCADE,
FOREIGN KEY (guid) REFERENCES guid
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON active_dashboards TO apache;

CREATE TABLE dashboard_switches (
guid text NOT NULL,
dbase_config text NOT NULL,
attribute text NOT NULL,
value boolean NOT NULL,
PRIMARY KEY (guid,dbase_config,attribute),
FOREIGN KEY (guid) REFERENCES guid
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON dashboard_switches TO apache;

