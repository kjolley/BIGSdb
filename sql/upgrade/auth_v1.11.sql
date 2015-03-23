DELETE FROM sessions;
ALTER TABLE sessions ADD state text NOT NULL;
ALTER TABLE sessions ADD username text;
ALTER TABLE sessions ADD reset_password boolean;

ALTER TABLE users ADD algorithm text;
UPDATE users SET algorithm = 'md5';
ALTER TABLE users ALTER COLUMN algorithm SET NOT NULL;
ALTER TABLE users ADD cost int;
ALTER TABLE users ADD salt text;
ALTER TABLE users ADD reset_password boolean;

CREATE TABLE clients (
application text NOT NULL,
version text NOT NULL,
client_id text NOT NULL UNIQUE,
client_secret text NOT NULL,
default_permission text NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (application,version),
CONSTRAINT c_default_permission CHECK (default_permission IN ( 'allow', 'deny'))
);

GRANT SELECT ON clients TO apache;

CREATE TABLE client_permissions (
client_id text NOT NULL,
dbase text NOT NULL,
authorize text NOT NULL,
access text NOT NULL,
PRIMARY KEY (client_id,dbase),
CONSTRAINT cp_client_id FOREIGN KEY (client_id) REFERENCES clients(client_id)
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT cp_authorize CHECK (authorize IN ( 'allow', 'deny')),
CONSTRAINT cp_access CHECK (access IN ('R', 'RW'))
);

GRANT SELECT ON client_permissions TO apache;

CREATE TABLE request_tokens (
token text NOT NULL,
secret text NOT NULL,
client_id text NOT NULL,
nonce text NOT NULL,
timestamp int NOT NULL,
start_time int NOT NULL,
username text,
dbase text,
verifier text,
redeemed boolean,
PRIMARY KEY (token),
UNIQUE (nonce, timestamp),
CONSTRAINT rt_client_id FOREIGN KEY (client_id) REFERENCES clients(client_id)
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT rt_username_dbase FOREIGN KEY (username,dbase) REFERENCES users(name,dbase)
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,DELETE,INSERT ON request_tokens TO apache;

CREATE TABLE access_tokens (
token text NOT NULL,
secret text NOT NULL,
client_id text NOT NULL,
datestamp date NOT NULL,
username text NOT NULL,
dbase text NOT NULL,
PRIMARY KEY (token),
CONSTRAINT at_client_id FOREIGN KEY (client_id) REFERENCES clients(client_id)
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT at_username_dbase FOREIGN KEY (username,dbase) REFERENCES users(name,dbase)
ON DELETE CASCADE
ON UPDATE CASCADE,
UNIQUE (client_id,username,dbase)
);

GRANT SELECT,UPDATE,DELETE,INSERT ON access_tokens TO apache;

CREATE TABLE api_sessions (
dbase text NOT NULL,
username text NOT NULL,
client_id text NOT NULL,
session text NOT NULL,
secret text NOT NULL,
nonce text NOT NULL,
timestamp int NOT NULL,
start_time int NOT NULL,
UNIQUE (nonce, timestamp),
PRIMARY KEY (dbase,session),
CONSTRAINT as_client_id FOREIGN KEY (client_id) REFERENCES clients(client_id)
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT as_username_dbase FOREIGN KEY (username,dbase) REFERENCES users(name,dbase)
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,DELETE,INSERT ON api_sessions TO apache;
