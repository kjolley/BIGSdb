CREATE TABLE users (
dbase text NOT NULL,
name text NOT NULL,
password text NOT NULL,
algorithm text NOT NULL,
cost int,
salt text,
ip_address text,
reset_password boolean,
date_entered date,
datestamp date,
last_login date,
interface text,
user_agent text,
PRIMARY KEY (dbase,name)
);

GRANT SELECT,UPDATE,DELETE,INSERT ON users TO apache;

CREATE TABLE sessions (
dbase text NOT NULL,
username text,
session text NOT NULL,
state text NOT NULL,
start_time int NOT NULL,
reset_password boolean,
PRIMARY KEY (dbase,session)
);

GRANT SELECT,UPDATE,DELETE,INSERT ON sessions TO apache;

CREATE TABLE clients (
application text NOT NULL,
version text NOT NULL,
client_id text NOT NULL UNIQUE,
client_secret text NOT NULL,
default_permission text NOT NULL,
default_submission bool NOT NULL,
default_curation bool NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (application,version),
CONSTRAINT c_default_permission CHECK (default_permission IN ( 'allow', 'deny'))
);

GRANT SELECT ON clients TO apache;

CREATE TABLE client_permissions (
client_id text NOT NULL,
dbase text NOT NULL,
authorize text NOT NULL,
submission bool NOT NULL,
curation bool NOT NULL,
PRIMARY KEY (client_id,dbase),
CONSTRAINT cp_client_id FOREIGN KEY (client_id) REFERENCES clients(client_id)
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT cp_authorize CHECK (authorize IN ( 'allow', 'deny'))
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

