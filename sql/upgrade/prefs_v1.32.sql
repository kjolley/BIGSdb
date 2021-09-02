CREATE TABLE primary_dashboard (
guid text NOT NULL,
dbase_config text NOT NULL,
attribute text NOT NULL,
value text NOT NULL,
PRIMARY KEY (guid,dbase_config,attribute),
CONSTRAINT conguid FOREIGN KEY (guid) REFERENCES guid
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON primary_dashboard TO apache;
