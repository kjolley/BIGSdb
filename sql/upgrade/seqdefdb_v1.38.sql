ALTER TABLE submissions ADD dataset text;

CREATE TABLE curator_configs (
user_id integer NOT NULL,
dbase_config text NOT NULL,
curator integer NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (user_id,dbase_config),
CONSTRAINT cc_user_id FOREIGN KEY (user_id) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT cc_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON curator_configs TO apache;
