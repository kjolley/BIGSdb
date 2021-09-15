CREATE TABLE dashboards (
id bigserial NOT NULL UNIQUE, 
guid text NOT NULL,
dbase_config text NOT NULL,
data jsonb NOT NULL,
PRIMARY KEY (id),
FOREIGN KEY (guid) REFERENCES guid
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON dashboards TO apache;
GRANT USAGE,SELECT ON SEQUENCE dashboards_id_seq TO apache;

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
