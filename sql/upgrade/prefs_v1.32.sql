CREATE TABLE dashboards (
id bigserial NOT NULL UNIQUE, 
guid text NOT NULL,
dbase_config text NOT NULL,
name text NOT NULL,
data jsonb NOT NULL,
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
BEGIN
    IF NEW.name IS NULL THEN
    	SELECT COUNT(*) INTO dashboard_count FROM dashboards WHERE (guid,dbase_config)=(NEW.guid,NEW.dbase_config);
    	NEW.name := 'dashboard#' || LPAD((dashboard_count+1)::text,3,'0');
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
