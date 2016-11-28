CREATE TABLE users (
user_name text NOT NULL UNIQUE,
surname text NOT NULL,
first_name text NOT NULL,
email text NOT NULL,
affiliation text NOT NULL,
date_entered date NOT NULL,
datestamp date NOT NULL,
status text NOT NULL,
validate_start int,
PRIMARY KEY (user_name)
);

GRANT SELECT,UPDATE,INSERT,DELETE ON users TO apache;

CREATE TABLE permissions (
user_name text NOT NULL,
permission text NOT NULL,
curator text NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (user_name,permission),
CONSTRAINT p_user_name FOREIGN KEY (user_name) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT p_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON permissions TO apache;

CREATE TABLE available_resources (
dbase_config text NOT NULL UNIQUE,
dbase_name text NOT NULL,
description text,
auto_registration boolean,
PRIMARY KEY (dbase_config)
);

GRANT SELECT,UPDATE,INSERT,DELETE ON available_resources TO apache;

CREATE TABLE registered_resources (
dbase_config text NOT NULL UNIQUE,
PRIMARY KEY (dbase_config),
auto_registration boolean,
CONSTRAINT rr_dbase_config FOREIGN KEY (dbase_config) REFERENCES available_resources
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON registered_resources TO apache;

CREATE OR REPLACE LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION update_auto_registration() RETURNS TRIGGER AS $update_auto_registration$
	BEGIN
		UPDATE registered_resources SET auto_registration=NEW.auto_registration WHERE dbase_config=NEW.dbase_config;
		RETURN NULL;
	END;
$update_auto_registration$ LANGUAGE plpgsql;

CREATE TRIGGER update_auto_registration AFTER UPDATE ON available_resources
	FOR EACH ROW
	EXECUTE PROCEDURE update_auto_registration();

CREATE TABLE registered_users (
dbase_config text NOT NULL,
user_name text NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (dbase_config,user_name),
CONSTRAINT ru_user_name FOREIGN KEY (user_name) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT ru_dbase_config FOREIGN KEY (dbase_config) REFERENCES registered_resources
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON registered_users TO apache;

CREATE TABLE pending_requests (
dbase_config text NOT NULL,
user_name text NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (dbase_config,user_name),
CONSTRAINT ru_user_name FOREIGN KEY (user_name) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT ru_dbase_config FOREIGN KEY (dbase_config) REFERENCES registered_resources
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON pending_requests TO apache;

CREATE TABLE invalid_usernames (
user_name text NOT NULL UNIQUE,
PRIMARY KEY (user_name)
);

GRANT SELECT,UPDATE,INSERT,DELETE ON invalid_usernames TO apache;

CREATE TABLE history (
timestamp timestamptz NOT NULL,
user_name text NOT NULL,
field text NOT NULL,
old text NOT NULL,
new text NOT NUll,
PRIMARY KEY (timestamp,user_name,field),
CONSTRAINT h_user_name FOREIGN KEY (user_name) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON history TO apache;
