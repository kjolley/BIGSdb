CREATE TABLE api_keys (
dbase text NOT NULL,
username text NOT NULL,
key text NOT NULL,
datestamp date NOT NULL,
ban boolean NOT NULL,
PRIMARY KEY (dbase,username),
CONSTRAINT ak_dbase_user FOREIGN KEY (dbase,username) REFERENCES users(dbase,name)
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,DELETE,INSERT ON api_keys TO apache;
