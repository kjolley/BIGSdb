CREATE TABLE users (
dbase text NOT NULL,
name text NOT NULL,
password text NOT NULL,
ip_address text,
PRIMARY KEY (dbase,name)
);

GRANT SELECT,UPDATE,DELETE,INSERT ON users TO apache;

CREATE TABLE sessions (
dbase text NOT NULL,
session text NOT NULL,
start_time int NOT NULL,
PRIMARY KEY (dbase,session)
);

GRANT SELECT,UPDATE,DELETE,INSERT ON sessions TO apache;
