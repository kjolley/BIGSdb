CREATE TABLE users (
dbase text NOT NULL,
name text NOT NULL,
password text NOT NULL,
algorithm text NOT NULL,
cost int,
salt text,
ip_address text,
reset_password boolean,
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
client_id text NOT NULL,
client_secret text NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (application, version)
);

GRANT SELECT ON clients TO apache;
